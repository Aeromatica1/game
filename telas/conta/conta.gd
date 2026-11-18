extends Control
## Tela de conta: mostra usuário / e-mail / senha, permite editar cada um pelo lápis,
## sair (logout) e deletar a conta. Autoloads necessários: Supabase, GameState.
##
## Edição: lápis -> campo fica editável. Enter (ou o lápis de novo) salva; Esc cancela.
## A senha real NUNCA é recuperável (o servidor só guarda o hash): mostramos "********" e,
## ao editar, o jogador digita a NOVA senha (visível enquanto digita, para evitar erro de digitação).
##
## Requer no banco (banco/conta.sql): alterar_username() e deletar_minha_conta().

## Emitido após logout ou remoção da conta; o GerenciadorTelas volta ao menu.
signal sessao_encerrada

const Validacao = preload("res://telas/login/validacao.gd")
const MASCARA_SENHA := "********"
const COR_EDITANDO := Color(0.5, 1.0, 0.6)

@onready var usuario_campo: LineEdit = $ContaArea/VBoxContainer/UsuarioArea/UsuarioCampo
@onready var email_campo: LineEdit = $ContaArea/VBoxContainer/EmailArea/EmailCampo
@onready var senha_campo: LineEdit = $ContaArea/VBoxContainer/SenhaArea/SenhaCampo
@onready var usuario_edit: TextureButton = $ContaArea/VBoxContainer/UsuarioArea/EditUsuario
@onready var email_edit: TextureButton = $ContaArea/VBoxContainer/EmailArea/EditEmail
@onready var senha_edit: TextureButton = $ContaArea/VBoxContainer/SenhaArea/EditSenha
@onready var status_texto: RichTextLabel = $ContaArea/VBoxContainer/StatusTexto
@onready var apagar_link: LinkButton = $ContaArea/VBoxContainer/ApagarArea/ApagarLink
@onready var sair_link: LinkButton = $ContaArea/VBoxContainer/LogoutArea/SairLink

var _botoes: Dictionary = {}          # LineEdit -> TextureButton (lápis)
var _editando: LineEdit = null
var _ocupado := false
var _dialogo: ConfirmationDialog


func _ready() -> void:
	usuario_campo.max_length = Validacao.USERNAME_MAX
	email_campo.max_length = Validacao.EMAIL_MAX
	senha_campo.max_length = Validacao.SENHA_MAX

	_botoes = {usuario_campo: usuario_edit, email_campo: email_edit, senha_campo: senha_edit}
	for campo: LineEdit in _botoes:
		campo.editable = false
		campo.text_submitted.connect(func(_t): _salvar())
		campo.text_changed.connect(func(_t): _limpar_status())
		campo.gui_input.connect(_on_campo_gui_input)
		(_botoes[campo] as TextureButton).pressed.connect(_on_lapis.bind(campo))
	usuario_edit.tooltip_text = "Editar usuário"
	email_edit.tooltip_text = "Editar e-mail"
	senha_edit.tooltip_text = "Editar senha"

	apagar_link.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
	apagar_link.pressed.connect(_on_apagar_pressed)
	sair_link.pressed.connect(_on_sair_pressed)

	_dialogo = ConfirmationDialog.new()
	_dialogo.title = "Deletar conta"
	_dialogo.dialog_text = "Tem certeza? Sua conta e TODOS os seus saves serão apagados permanentemente. Essa ação não pode ser desfeita."
	_dialogo.dialog_autowrap = true
	_dialogo.min_size = Vector2i(480, 160)
	_dialogo.ok_button_text = "Deletar"
	_dialogo.cancel_button_text = "Cancelar"
	_dialogo.confirmed.connect(_apagar_conta)
	add_child(_dialogo)

	# O GerenciadorTelas só alterna `visible`: recarrega os dados a cada vez que a tela abre.
	visibility_changed.connect(_on_visibilidade)
	if visible:
		_preencher()


func _on_visibilidade() -> void:
	if visible:
		_preencher()
	else:
		_sair_da_edicao()
		_limpar_status()


# ------------------------- Exibição -------------------------
func _username_atual() -> String:
	var nome := GameState.username()
	return nome if nome != "" else Supabase.username


func _preencher() -> void:
	_sair_da_edicao()
	_limpar_status()
	usuario_campo.text = _username_atual()
	email_campo.text = Supabase.email
	senha_campo.text = MASCARA_SENHA
	if not Supabase.is_logged_in():
		_erro("Você não está logado.")
	_atualizar_estado()


func _atualizar_estado() -> void:
	var logado := Supabase.is_logged_in()
	for campo: LineEdit in _botoes:
		(_botoes[campo] as TextureButton).disabled = _ocupado or not logado
	apagar_link.disabled = _ocupado or not logado
	sair_link.disabled = _ocupado or not logado


func _set_ocupado(v: bool) -> void:
	_ocupado = v
	if _editando != null:
		_editando.editable = not v
	_atualizar_estado()


# ------------------------- Edição -------------------------
func _on_lapis(campo: LineEdit) -> void:
	if _ocupado:
		return
	if _editando == campo:
		_salvar()                       # segundo clique no lápis = confirmar
		return
	_sair_da_edicao()                   # só um campo por vez; descarta o anterior
	_limpar_status()
	_editando = campo
	campo.editable = true
	if campo == senha_campo:
		campo.secret = false
		campo.text = ""
		campo.placeholder_text = "Nova senha"
	(_botoes[campo] as TextureButton).modulate = COR_EDITANDO
	(_botoes[campo] as TextureButton).tooltip_text = "Salvar (Enter)"
	campo.grab_focus()
	campo.caret_column = campo.text.length()
	_aviso("Enter ou lápis: salvar  |  Esc: cancelar")


func _on_campo_gui_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and evento.keycode == KEY_ESCAPE and _editando != null and not _ocupado:
		_sair_da_edicao()
		_limpar_status()
		accept_event()


## Encerra a edição e restaura os valores atuais (descarta o que foi digitado).
func _sair_da_edicao() -> void:
	_editando = null
	for campo: LineEdit in _botoes:
		campo.editable = false
		campo.release_focus()
		campo.modulate = Color.WHITE
		var b: TextureButton = _botoes[campo]
		b.modulate = Color.WHITE
	usuario_edit.tooltip_text = "Editar usuário"
	email_edit.tooltip_text = "Editar e-mail"
	senha_edit.tooltip_text = "Editar senha"
	usuario_campo.text = _username_atual()
	email_campo.text = Supabase.email
	senha_campo.text = MASCARA_SENHA if Supabase.is_logged_in() else ""
	senha_campo.placeholder_text = "Senha"


func _salvar() -> void:
	if _ocupado or _editando == null:
		return
	if _editando == usuario_campo:
		await _salvar_username()
	elif _editando == email_campo:
		await _salvar_email()
	elif _editando == senha_campo:
		await _salvar_senha()


func _salvar_username() -> void:
	var novo := Validacao.limpar_username(usuario_campo.text)
	usuario_campo.text = novo
	var erro := Validacao.validar_username(novo)
	if erro != "":
		_marcar(usuario_campo, true)
		_erro(erro)
		return
	if novo == _username_atual():
		_sair_da_edicao()
		return

	_limpar_status()
	_set_ocupado(true)
	_aviso("Salvando...")
	var r := await Supabase.alterar_username(novo)
	if not is_inside_tree():
		return
	_set_ocupado(false)
	if not r.ok:
		_marcar(usuario_campo, true)
		_erro(_traduzir(r))
		return
	_sincronizar_game_state()
	_sair_da_edicao()
	_sucesso("Nome de usuário atualizado!")


func _salvar_email() -> void:
	var novo := Validacao.limpar_email(email_campo.text)
	email_campo.text = novo
	var erro := Validacao.validar_email(novo)
	if erro != "":
		_marcar(email_campo, true)
		_erro(erro)
		return
	if novo == Supabase.email:
		_sair_da_edicao()
		return

	_limpar_status()
	_set_ocupado(true)
	_aviso("Salvando...")
	var r := await Supabase.atualizar_usuario({"email": novo})
	if not is_inside_tree():
		return
	_set_ocupado(false)
	if not r.ok:
		_marcar(email_campo, true)
		_erro(_traduzir(r))
		return
	_sincronizar_game_state()
	_sair_da_edicao()
	var d: Dictionary = r.data if r.data is Dictionary else {}
	# Com confirmação de e-mail ligada no Supabase o e-mail só troca depois do clique no link.
	if str(d.get("new_email", "")) != "":
		_sucesso("Enviamos um e-mail de confirmação para %s. O e-mail da conta muda depois que você confirmar." % novo)
	else:
		_sucesso("E-mail atualizado!")


func _salvar_senha() -> void:
	var senha := senha_campo.text
	var erro := Validacao.validar_senha(senha, _username_atual(), Supabase.email)
	if erro != "":
		_marcar(senha_campo, true)
		_erro(erro)
		return

	_limpar_status()
	_set_ocupado(true)
	_aviso("Salvando...")
	var r := await Supabase.atualizar_usuario({"password": senha})
	if not is_inside_tree():
		return
	_set_ocupado(false)
	if not r.ok:
		_marcar(senha_campo, true)
		_erro(_traduzir(r))
		return
	_sair_da_edicao()
	_sucesso("Senha atualizada!")


## Mantém o cache do GameState (usado em outras telas) igual ao servidor.
func _sincronizar_game_state() -> void:
	if GameState.conta_pronta:
		GameState.usuario["username"] = Supabase.username
		GameState.usuario["email"] = Supabase.email


# ------------------------- Sair / deletar -------------------------
func _on_sair_pressed() -> void:
	if _ocupado:
		return
	_sair_da_edicao()
	_set_ocupado(true)
	await Supabase.sign_out()          # limpa a sessão local mesmo se a rede falhar
	if not is_inside_tree():
		return
	_set_ocupado(false)
	sessao_encerrada.emit()


func _on_apagar_pressed() -> void:
	if _ocupado:
		return
	_sair_da_edicao()
	_limpar_status()
	_dialogo.popup_centered()


func _apagar_conta() -> void:
	if _ocupado:
		return
	_set_ocupado(true)
	_aviso("Deletando conta...")
	var r := await Supabase.deletar_conta()
	if not is_inside_tree():
		return
	_set_ocupado(false)
	if not r.ok:
		_erro(_traduzir(r))
		return
	sessao_encerrada.emit()


# ------------------------- Mensagens -------------------------
func _traduzir(r: Dictionary) -> String:
	var codigo := str(r.get("error_code", ""))
	var msg := str(r.get("error", "")).to_lower()
	if codigo in ["email_exists", "user_already_exists"]:
		return "Este e-mail já está em uso por outra conta."
	if codigo == "23505" or "já está em uso" in msg or "duplicate key" in msg:
		return "Este nome de usuário já está em uso. Escolha outro."
	if codigo == "PGRST202":
		return "Recurso ainda não instalado no servidor (rode banco/conta.sql no Supabase)."
	return Validacao.traduzir_erro(r)


func _aviso(texto: String) -> void:
	status_texto.text = "[color=#cfd8e3]" + texto + "[/color]"


func _sucesso(texto: String) -> void:
	status_texto.text = "[color=#6bff8a]" + texto + "[/color]"


func _erro(texto: String) -> void:
	status_texto.text = "[color=#ff6b6b]" + texto + "[/color]"


func _limpar_status() -> void:
	status_texto.text = ""
	for campo: LineEdit in _botoes:
		_marcar(campo, false)


func _marcar(campo: Control, invalido: bool) -> void:
	campo.modulate = Color(1.0, 0.65, 0.65) if invalido else Color.WHITE
