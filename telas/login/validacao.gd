extends RefCounted
## Validações e mensagens de erro compartilhadas por login e cadastro.
## Uso:  const Validacao = preload("res://login/validacao.gd")
##
## IMPORTANTE: validar no cliente é só conforto (feedback rápido). A garantia real
## está no servidor (Supabase Auth + constraints do banco); nunca confie só aqui.

const USERNAME_MIN := 3
const USERNAME_MAX := 20
const SENHA_MIN := 8
const SENHA_MAX := 72        # o bcrypt do Supabase só considera até 72 bytes
const EMAIL_MAX := 254       # limite do RFC 5321

static var _re_email: RegEx
static var _re_username: RegEx
static var _re_letra: RegEx
static var _re_digito: RegEx


static func _compilar(padrao: String) -> RegEx:
	var re := RegEx.new()
	re.compile(padrao)
	return re


# ------------------------- Normalização (trim) -------------------------
static func limpar_email(texto: String) -> String:
	return texto.strip_edges().to_lower()      # e-mail não diferencia maiúsculas

static func limpar_username(texto: String) -> String:
	return texto.strip_edges()
# Senha NÃO recebe trim: espaços podem ser intencionais.


# ------------------------- Validadores (retornam "" se OK) -------------------------
static func validar_email(email: String) -> String:
	if email.is_empty():
		return "Informe seu e-mail."
	if email.length() > EMAIL_MAX:
		return "E-mail muito longo (máx. %d caracteres)." % EMAIL_MAX
	if _re_email == null:
		# parte local @ domínio com pelo menos um ponto e TLD de 2+ letras
		_re_email = _compilar("^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9\\-]+(\\.[A-Za-z0-9\\-]+)*\\.[A-Za-z]{2,}$")
	if _re_email.search(email) == null or ".." in email or email.begins_with(".") or "@." in email:
		return "Digite um e-mail válido (ex.: nome@dominio.com)."
	return ""


static func validar_username(nome: String) -> String:
	if nome.is_empty():
		return "Informe um nome de usuário."
	if nome.length() < USERNAME_MIN:
		return "O nome de usuário precisa ter pelo menos %d caracteres." % USERNAME_MIN
	if nome.length() > USERNAME_MAX:
		return "O nome de usuário pode ter no máximo %d caracteres." % USERNAME_MAX
	if _re_username == null:
		_re_username = _compilar("^[A-Za-z0-9_]+$")
	if _re_username.search(nome) == null:
		return "Use apenas letras, números e _ (sem espaços ou acentos)."
	return ""


static func validar_senha(senha: String, username := "", email := "") -> String:
	if senha.is_empty():
		return "Informe uma senha."
	if senha.length() < SENHA_MIN:
		return "A senha precisa ter pelo menos %d caracteres." % SENHA_MIN
	if senha.to_utf8_buffer().size() > SENHA_MAX:
		return "A senha pode ter no máximo %d caracteres." % SENHA_MAX
	if senha.strip_edges().is_empty():
		return "A senha não pode ser só espaços."
	if _re_letra == null:
		_re_letra = _compilar("[A-Za-z]")
		_re_digito = _compilar("[0-9]")
	if _re_letra.search(senha) == null or _re_digito.search(senha) == null:
		return "A senha precisa ter letras e números."
	var baixo := senha.to_lower()
	if (username != "" and baixo == username.to_lower()) or (email != "" and baixo == email.to_lower()):
		return "A senha não pode ser igual ao usuário ou ao e-mail."
	return ""


static func validar_confirmacao(senha: String, confirmacao: String) -> String:
	if confirmacao.is_empty():
		return "Confirme sua senha."
	if senha != confirmacao:
		return "As senhas não coincidem."
	return ""


# ------------------------- Mensagens de erro do servidor -------------------------
## Recebe o dicionário retornado por Supabase.request() e devolve um texto amigável.
static func traduzir_erro(r: Dictionary) -> String:
	var codigo := str(r.get("error_code", ""))
	var http := int(r.get("code", 0))
	var msg := str(r.get("error", "")).to_lower()

	match codigo:
		"invalid_credentials":
			return "E-mail ou senha incorretos."     # genérico de propósito: não revela se o e-mail existe
		"email_not_confirmed":
			return "Confirme seu e-mail antes de entrar. Verifique sua caixa de entrada (e o spam)."
		"user_already_exists", "email_exists":
			return "Este e-mail já está cadastrado. Tente fazer login."
		"weak_password":
			return "Senha muito fraca ou muito comum. Escolha uma senha mais forte."
		"over_email_send_rate_limit":
			return "Muitos e-mails de confirmação foram enviados. Aguarde alguns minutos e tente de novo."
		"over_request_rate_limit", "over_sms_send_rate_limit":
			return "Muitas tentativas seguidas. Aguarde um pouco e tente novamente."
		"signup_disabled":
			return "Novos cadastros estão desativados no momento."
		"email_address_invalid", "validation_failed":
			return "O e-mail informado não foi aceito. Confira e tente de novo."
		"request_failed":
			return "Não foi possível conectar ao servidor."
	if http == 429:
		return "Muitas tentativas seguidas. Aguarde um pouco e tente novamente."
	if http == 0 or msg.begins_with("sem conexão"):
		return "Sem conexão com o servidor. Verifique sua internet."
	# O trigger do banco recusou o perfil (username repetido/inválido na corrida entre
	# a checagem e o cadastro): o GoTrue devolve só "Database error saving new user".
	if "database error" in msg:
		return "Esse nome de usuário não está disponível. Escolha outro."
	if http >= 500:
		return "O servidor teve um problema. Tente novamente em instantes."
	push_warning("Erro não mapeado: %s" % str(r))
	return "Algo deu errado. Tente novamente."
