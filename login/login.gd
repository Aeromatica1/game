extends Control
## Tela de login. Autoloads necessários: Supabase.

signal login_sucesso

const Validacao = preload("res://login/validacao.gd")
const MAX_FALHAS := 5          # falhas seguidas até bloquear o botão por um tempo (só conforto; o limite real é do Supabase)
const BLOQUEIO_SEG := 30

## Cena aberta após o login (ex.: menu principal). Vazio = só emite o sinal.
@export_file("*.tscn") var cena_apos_login := ""
@export_file("*.tscn") var cena_cadastro := "res://cadastro/cadastro.tscn"

@onready var email_campo: LineEdit = $LoginArea/VBoxContainer/EmailArea/EmailCampo
@onready var senha_campo: LineEdit = $LoginArea/VBoxContainer/SenhaArea/SenhaCampo
@onready var mostrar_senha: CheckBox = $LoginArea/VBoxContainer/MostrarSenha
@onready var enviar_btn: Button = $LoginArea/VBoxContainer/EnviarLogin
@onready var cadastro_link: LinkButton = $LoginArea/VBoxContainer/RegistrarArea/RegistrarLink
@onready var erro_texto: RichTextLabel = $LoginArea/VBoxContainer/ErroArea/ErroTexto

var _ocupado := false
var _falhas := 0


func _ready() -> void:
	email_campo.max_length = Validacao.EMAIL_MAX
	senha_campo.max_length = Validacao.SENHA_MAX
	senha_campo.secret = true
	mostrar_senha.toggled.connect(func(visivel: bool): senha_campo.secret = not visivel)

	email_campo.text_submitted.connect(func(_t): senha_campo.grab_focus())
	senha_campo.text_submitted.connect(func(_t): _enviar())
	enviar_btn.pressed.connect(_enviar)
	cadastro_link.pressed.connect(_ir_cadastro)
	# digitar de novo limpa o aviso de erro
	email_campo.text_changed.connect(func(_t): _limpar_erro())
	senha_campo.text_changed.connect(func(_t): _limpar_erro())

	email_campo.grab_focus()
	_tentar_sessao_salva()


# ------------------------- Fluxo -------------------------
func _tentar_sessao_salva() -> void:
	_set_ocupado(true, "Verificando sessão...")
	var ok := await Supabase.restore_session()
	if not is_inside_tree():
		return
	_set_ocupado(false)
	if ok:
		_sucesso()


func _enviar() -> void:
	if _ocupado or enviar_btn.disabled:
		return
	var email := Validacao.limpar_email(email_campo.text)
	email_campo.text = email                      # mostra o texto já com trim
	var senha := senha_campo.text

	var erros: Array[String] = []
	var e := Validacao.validar_email(email)
	_marcar(email_campo, e != "")
	if e != "":
		erros.append(e)
	var senha_vazia := senha.is_empty()
	_marcar(senha_campo, senha_vazia)
	if senha_vazia:
		erros.append("Informe sua senha.")
	if not erros.is_empty():
		_mostrar_erros(erros)
		return

	_limpar_erro()
	_set_ocupado(true, "Entrando...")
	var r := await Supabase.sign_in(email, senha)
	if not is_inside_tree():
		return
	_set_ocupado(false)

	if r.ok:
		senha_campo.text = ""
		_falhas = 0
		_sucesso()
		return

	_falhas += 1
	_mostrar_erros([Validacao.traduzir_erro(r)])
	if r.code == 429:
		_bloquear(60)
	elif _falhas >= MAX_FALHAS:
		_falhas = 0
		_bloquear(BLOQUEIO_SEG)


func _sucesso() -> void:
	login_sucesso.emit()
	if cena_apos_login != "":
		get_tree().change_scene_to_file(cena_apos_login)
	else:
		erro_texto.text = "[color=#6bff8a]Login realizado![/color]"


func _ir_cadastro() -> void:
	if cena_cadastro != "":
		get_tree().change_scene_to_file(cena_cadastro)


# ------------------------- UI -------------------------
func _set_ocupado(v: bool, texto := "") -> void:
	_ocupado = v
	email_campo.editable = not v
	senha_campo.editable = not v
	enviar_btn.disabled = v
	enviar_btn.text = texto if v else "Entrar"


func _bloquear(segundos: int) -> void:
	enviar_btn.disabled = true
	for restante in range(segundos, 0, -1):
		if not is_inside_tree():
			return
		enviar_btn.text = "Aguarde %ds" % restante
		await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		enviar_btn.disabled = false
		enviar_btn.text = "Entrar"


func _mostrar_erros(erros: Array[String]) -> void:
	erro_texto.text = "[color=#ff6b6b]" + "\n".join(erros) + "[/color]"


func _limpar_erro() -> void:
	erro_texto.text = ""
	_marcar(email_campo, false)
	_marcar(senha_campo, false)


func _marcar(campo: Control, invalido: bool) -> void:
	campo.modulate = Color(1.0, 0.65, 0.65) if invalido else Color.WHITE
