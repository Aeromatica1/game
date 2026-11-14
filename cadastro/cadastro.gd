extends Control
## Tela de cadastro. Autoloads necessários: Supabase.
## Requer no banco a função username_disponivel() (aeromatica_migracao_v3.sql).

signal cadastro_sucesso

const Validacao = preload("res://login/validacao.gd")
const COOLDOWN_APOS_CADASTRO := 60   # evita reenviar e-mails de confirmação (rate limit do Supabase)

@export_file("*.tscn") var cena_apos_login := ""
@export_file("*.tscn") var cena_login := "res://login/login.tscn"

@onready var usuario_campo: LineEdit = $CadastroArea/VBoxContainer/UsuarioArea/UsuarioCampo
@onready var email_campo: LineEdit = $CadastroArea/VBoxContainer/EmailArea/EmailCampo
@onready var senha_campo: LineEdit = $CadastroArea/VBoxContainer/SenhaArea/SenhaCampo
@onready var confirmar_campo: LineEdit = $CadastroArea/VBoxContainer/ConfirmarArea/ConfirmarCampo
@onready var mostrar_senha: CheckBox = $CadastroArea/VBoxContainer/MostrarSenha
@onready var enviar_btn: Button = $CadastroArea/VBoxContainer/EnviarCadastro
@onready var login_link: LinkButton = $CadastroArea/VBoxContainer/LogarArea/LogarLink
@onready var erro_texto: RichTextLabel = $CadastroArea/VBoxContainer/ErroArea/ErroTexto

var _ocupado := false


func _ready() -> void:
	usuario_campo.max_length = Validacao.USERNAME_MAX
	email_campo.max_length = Validacao.EMAIL_MAX
	senha_campo.max_length = Validacao.SENHA_MAX
	confirmar_campo.max_length = Validacao.SENHA_MAX
	senha_campo.secret = true
	confirmar_campo.secret = true
	mostrar_senha.toggled.connect(func(visivel: bool):
		senha_campo.secret = not visivel
		confirmar_campo.secret = not visivel)

	# Enter avança para o próximo campo; no último, envia
	usuario_campo.text_submitted.connect(func(_t): email_campo.grab_focus())
	email_campo.text_submitted.connect(func(_t): senha_campo.grab_focus())
	senha_campo.text_submitted.connect(func(_t): confirmar_campo.grab_focus())
	confirmar_campo.text_submitted.connect(func(_t): _enviar())
	enviar_btn.pressed.connect(_enviar)
	login_link.pressed.connect(_ir_login)
	for campo in [usuario_campo, email_campo, senha_campo, confirmar_campo]:
		campo.text_changed.connect(func(_t): _limpar_erro())

	usuario_campo.grab_focus()


# ------------------------- Fluxo -------------------------
func _enviar() -> void:
	if _ocupado or enviar_btn.disabled:
		return

	# 1) trim + normalização (a senha fica como digitada)
	var username := Validacao.limpar_username(usuario_campo.text)
	var email := Validacao.limpar_email(email_campo.text)
	var senha := senha_campo.text
	var confirmacao := confirmar_campo.text
	usuario_campo.text = username
	email_campo.text = email

	# 2) validação local de todos os campos (mostra todos os erros de uma vez)
	var erros: Array[String] = []
	_checar(usuario_campo, Validacao.validar_username(username), erros)
	_checar(email_campo, Validacao.validar_email(email), erros)
	_checar(senha_campo, Validacao.validar_senha(senha, username, email), erros)
	_checar(confirmar_campo, Validacao.validar_confirmacao(senha, confirmacao), erros)
	if not erros.is_empty():
		_mostrar_erros(erros)
		return

	_limpar_erro()

	# 3) nome de usuário já tomado? (consulta leve, sem login)
	_set_ocupado(true, "Verificando nome de usuário...")
	var disp := await Supabase.call_rpc("username_disponivel", {"p_username": username})
	if not is_inside_tree():
		return
	if not disp.ok:
		_set_ocupado(false)
		_mostrar_erros(["Não foi possível verificar o nome de usuário. " + Validacao.traduzir_erro(disp)])
		return
	if disp.data != true:
		_set_ocupado(false)
		_marcar(usuario_campo, true)
		_mostrar_erros(["Este nome de usuário já está em uso. Escolha outro."])
		return

	# 4) cria a conta
	_set_ocupado(true, "Criando conta...")
	var r := await Supabase.sign_up(email, senha, username)
	if not is_inside_tree():
		return
	_set_ocupado(false)

	if not r.ok:
		_mostrar_erros([Validacao.traduzir_erro(r)])
		if r.error_code == "over_email_send_rate_limit" or r.code == 429:
			_bloquear(COOLDOWN_APOS_CADASTRO)
		return

	var d: Dictionary = r.data if r.data is Dictionary else {}

	# 4a) confirmação de e-mail DESLIGADA no Supabase: já veio com sessão
	if d.has("access_token"):
		senha_campo.text = ""
		confirmar_campo.text = ""
		cadastro_sucesso.emit()
		if cena_apos_login != "":
			get_tree().change_scene_to_file(cena_apos_login)
		else:
			erro_texto.text = "[color=#6bff8a]Conta criada! Você já está logado.[/color]"
		return

	# 4b) confirmação de e-mail LIGADA: o Supabase devolve o usuário sem sessão.
	# Para e-mail já existente ele responde "sucesso" com identities vazio (anti-enumeração).
	var identidades: Variant = d.get("identities", null)
	if identidades is Array and identidades.is_empty():
		_marcar(email_campo, true)
		_mostrar_erros(["Este e-mail já está cadastrado. Tente fazer login."])
		return

	senha_campo.text = ""
	confirmar_campo.text = ""
	cadastro_sucesso.emit()
	erro_texto.text = "[color=#6bff8a]Conta criada! Enviamos um e-mail de confirmação para %s. Confirme e depois faça login.[/color]" % email
	_bloquear(COOLDOWN_APOS_CADASTRO)


func _ir_login() -> void:
	if cena_login != "":
		get_tree().change_scene_to_file(cena_login)


# ------------------------- UI -------------------------
func _checar(campo: Control, erro: String, erros: Array[String]) -> void:
	_marcar(campo, erro != "")
	if erro != "":
		erros.append(erro)


func _set_ocupado(v: bool, texto := "") -> void:
	_ocupado = v
	for campo in [usuario_campo, email_campo, senha_campo, confirmar_campo]:
		campo.editable = not v
	enviar_btn.disabled = v
	enviar_btn.text = texto if v else "Cadastrar"


func _bloquear(segundos: int) -> void:
	enviar_btn.disabled = true
	for restante in range(segundos, 0, -1):
		if not is_inside_tree():
			return
		enviar_btn.text = "Aguarde %ds" % restante
		await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		enviar_btn.disabled = false
		enviar_btn.text = "Cadastrar"


func _mostrar_erros(erros: Array[String]) -> void:
	erro_texto.text = "[color=#ff6b6b]" + "\n".join(erros) + "[/color]"


func _limpar_erro() -> void:
	erro_texto.text = ""
	for campo in [usuario_campo, email_campo, senha_campo, confirmar_campo]:
		_marcar(campo, false)


func _marcar(campo: Control, invalido: bool) -> void:
	campo.modulate = Color(1.0, 0.65, 0.65) if invalido else Color.WHITE
