
extends Node

@onready var cadastro: Control = $Cadastro
@onready var login: Control = $Login
@onready var menu_principal: Control = $MenuPrincipal
@onready var save_slot: Control = $SaveSlot
@onready var barra_usuario: CanvasLayer = $BarraUsuario
@onready var botao_voltar: Button = $BarraUsuario/Voltar

var cena_atual: Control
var historico_cenas: Array[Control] = []


func _ready() -> void:
	Supabase.restore_session()

	# Estado inicial
	for cena in [cadastro, login, menu_principal, save_slot]:
		cena.visible = false

	cena_atual = menu_principal
	cena_atual.visible = true

	historico_cenas.append(cena_atual)
	botao_voltar.visible = false
	
	login.login_sucesso.connect(_on_login_sucesso)
	cadastro.cadastro_sucesso.connect(_on_cadastro_sucesso)


# ==================== Navegação ====================

func _trocar_para(cena_nova: Control) -> void:
	if cena_nova == cena_atual:
		return

	cena_atual.visible = false
	cena_nova.visible = true

	cena_atual = cena_nova
	historico_cenas.append(cena_atual)

	botao_voltar.visible = historico_cenas.size() > 1


func _retornar() -> void:
	if historico_cenas.size() <= 1:
		return
		
	historico_cenas.pop_back()
	var cena_anterior: Control = historico_cenas.back()

	cena_atual.visible = false
	cena_anterior.visible = true

	cena_atual = cena_anterior

	botao_voltar.visible = historico_cenas.size() > 1


# ==================== Menu Principal ====================

func _on_botao_jogar_pressed() -> void:
	if not Supabase.is_logged_in():
		_trocar_para(login)
	else:
		_trocar_para(save_slot)


func _on_botao_opcoes_pressed() -> void:
	_trocar_para(login)


func _on_botao_sair_pressed() -> void:
	get_tree().quit()


# ==================== Cadastro ====================

func _on_registrar_link_pressed() -> void:
	_trocar_para(cadastro)

func _on_cadastro_sucesso() -> void:
	_trocar_para(save_slot)

# ==================== Login ====================

func _on_logar_link_pressed() -> void:
	_trocar_para(login)

func _on_login_sucesso() -> void:
	_trocar_para(save_slot)

# ==================== SaveSlot ====================

func _on_slot_3_pressed() -> void:
	get_tree().change_scene_to_file("res://mapa/mapa.tscn")


func _on_voltar_pressed() -> void:
	_retornar()
