extends Node
## Autoload "Supabase": cliente HTTP genérico + autenticação (GoTrue) + REST (PostgREST).
## Projeto > Configurações > Autoload: adicione este arquivo com o nome "Supabase".
##
## SEGURANÇA:
##  - Use APENAS a chave publicável (sb_publishable_...). NUNCA a secret/service_role no jogo.
##  - A proteção real é o RLS + RPCs no banco; esta chave é pública por design.
##  - Tokens ficam só em memória; o refresh token é guardado criptografado em user://.

signal session_changed(logged_in: bool)
signal _refresh_done

const SUPABASE_URL := "https://xovqiaqietshstdfjpoo.supabase.co"          # sempre https
const SUPABASE_KEY := "sb_publishable_9Lx4OsCoCikkOZee7HTqtg_fTFwyALX"
const TIMEOUT_SEC := 15.0
const SESSION_FILE := "user://session.cfg"

var access_token := ""
var refresh_token := ""
var expires_at := 0.0       # unix time
var user_id := ""
var _refreshing := false


func is_logged_in() -> bool:
	return access_token != ""


# ---------------------------------------------------------------------
# Requisição genérica. Sempre retorna:
#   { "ok": bool, "code": int, "data": Variant, "error": String, "error_code": String }
# Uso:  var r = await Supabase.request("/rest/v1/nivel_aeroporto?select=*")
# (await por chamada evita o problema de um único sinal compartilhado,
#  que misturaria respostas de requisições simultâneas)
# ---------------------------------------------------------------------
func request(path: String, method: int = HTTPClient.METHOD_GET, body: Variant = null,
		extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not path.begins_with("/auth/v1/"):
		await _ensure_fresh_token()

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	add_child(http)

	var headers := PackedStringArray([
		"apikey: " + SUPABASE_KEY,
		"Content-Type: application/json",
	])
	# A chave publicável não é um JWT: só enviamos Authorization quando há sessão.
	if access_token != "":
		headers.append("Authorization: Bearer " + access_token)
	headers.append_array(extra_headers)

	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(SUPABASE_URL + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null, "error": "Falha ao iniciar requisição (%d)" % err, "error_code": "request_failed"}

	var res: Array = await http.request_completed   # [result, code, headers, body]
	http.queue_free()

	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if text != "" else null
	var ok: bool = res[0] == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300

	var error := ""
	var error_code := ""
	if not ok:
		if res[0] != HTTPRequest.RESULT_SUCCESS:
			error = "Sem conexão com o servidor"
		elif data is Dictionary:
			# GoTrue (auth): "error_code" ex. "invalid_credentials", "over_email_send_rate_limit"
			# PostgREST: "code" ex. "P0001" (RAISE EXCEPTION), "message" com o texto
			error_code = str(data.get("error_code", data.get("code", "")))
			# PostgREST: "message"; GoTrue: "msg" / "error_description"
			error = str(data.get("message", data.get("msg", data.get("error_description", "Erro %d" % code))))
		else:
			error = "Erro %d" % code
	return {"ok": ok, "code": code, "data": data, "error": error, "error_code": error_code}


# ---------------------------------------------------------------------
# Autenticação
# ---------------------------------------------------------------------
func sign_up(email: String, password: String, username: String) -> Dictionary:
	var r := await request("/auth/v1/signup", HTTPClient.METHOD_POST,
		{"email": email, "password": password, "data": {"username": username}})
	# Com confirmação de e-mail ligada, não vem sessão: o jogador precisa confirmar e logar.
	if r.ok and r.data is Dictionary and r.data.has("access_token"):
		_set_session(r.data)
	return r


func sign_in(email: String, password: String) -> Dictionary:
	var r := await request("/auth/v1/token?grant_type=password", HTTPClient.METHOD_POST,
		{"email": email, "password": password})
	if r.ok:
		_set_session(r.data)
	return r


func sign_out() -> void:
	if is_logged_in():
		await request("/auth/v1/logout", HTTPClient.METHOD_POST)
	_clear_session()


## Tenta retomar a sessão salva (chame no _ready da tela inicial).
func restore_session() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(SESSION_FILE, _file_key()) != OK:
		return false
	refresh_token = cfg.get_value("s", "refresh_token", "")
	if refresh_token == "":
		return false
	return await refresh_session()


func refresh_session() -> bool:
	if _refreshing:
		await _refresh_done
		return is_logged_in()
	_refreshing = true
	var r := await request("/auth/v1/token?grant_type=refresh_token", HTTPClient.METHOD_POST,
		{"refresh_token": refresh_token})
	if r.ok:
		_set_session(r.data)
	else:
		_clear_session()
	_refreshing = false
	_refresh_done.emit()
	return r.ok


func _ensure_fresh_token() -> void:
	if access_token == "" or refresh_token == "":
		return
	if Time.get_unix_time_from_system() < expires_at - 60.0:
		return
	await refresh_session()


func _set_session(d: Dictionary) -> void:
	access_token = d.get("access_token", "")
	refresh_token = d.get("refresh_token", "")
	expires_at = float(d.get("expires_at", Time.get_unix_time_from_system() + float(d.get("expires_in", 3600))))
	user_id = str(d.get("user", {}).get("id", ""))
	var cfg := ConfigFile.new()
	cfg.set_value("s", "refresh_token", refresh_token)
	cfg.save_encrypted_pass(SESSION_FILE, _file_key())
	session_changed.emit(true)


func _clear_session() -> void:
	access_token = ""
	refresh_token = ""
	expires_at = 0.0
	user_id = ""
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))
	session_changed.emit(false)


# Chave amarrada ao dispositivo: o arquivo copiado para outro PC não abre.
# (Ofuscação razoável, não é cofre: quem controla a máquina do jogador ainda
#  pode extrair a sessão. Por isso o token tem validade curta e logout o revoga.)
func _file_key() -> String:
	return "aeromatica:" + OS.get_unique_id()


# ---------------------------------------------------------------------
# Helpers REST
# ---------------------------------------------------------------------
## Codifica valores de filtro: "?nome=eq." + Supabase.q("a&b") -> seguro contra injeção de parâmetros.
func q(value: Variant) -> String:
	return str(value).uri_encode()


## ATENÇÃO: não pode se chamar `rpc`, pois Node já tem um método `rpc()` (multiplayer).
func call_rpc(fn: String, args: Dictionary = {}) -> Dictionary:
	return await request("/rest/v1/rpc/" + fn, HTTPClient.METHOD_POST, args)
