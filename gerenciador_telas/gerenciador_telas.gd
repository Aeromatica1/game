extends Node

@onready var cadastro: Control = $Cadastro
@onready var login: Control = $Login
@onready var menu_principal: Control = $MenuPrincipal
@onready var save_slot: Control = $SaveSlot
@onready var block_blast: Control = $BlockBlast
@onready var minesweeper: Control = $Minesweeper

# ==================== Menu Principal ====================

func _ready() -> void:
	menu_principal.visible = true
	login.visible = false
	cadastro.visible = false
	save_slot.visible = false
	block_blast.visible = false
	minesweeper.visible = false

func _on_botao_jogar_pressed() -> void:
	save_slot.visible = true
	menu_principal.visible = false

func _on_botao_opcoes_pressed() -> void:
	cadastro.visible = true
	menu_principal.visible = false

func _on_botao_sair_pressed() -> void:
	get_tree().quit()


# ==================== Cadastro ====================

func _on_registrar_botao_pressed() -> void:
	cadastro.visible = true
	login.visible = false

func _on_enviar_cadastro_pressed() -> void:
	menu_principal.visible = true
	cadastro.visible = false


# ==================== Login ====================

func _on_logar_botao_pressed() -> void:
	login.visible = true
	cadastro.visible = false

func _on_enviar_login_pressed() -> void:
	menu_principal.visible = true
	login.visible = false


# ==================== SaveSlot ====================

func _on_add_1_pressed() -> void:
	block_blast.visible = true
	save_slot.visible = false

func _on_add_2_pressed() -> void:
	minesweeper.visible = true
	save_slot.visible = false

func _on_minesweeper_voltar_pressed() -> void:
	minesweeper.visible = false
	save_slot.visible = true

func _on_add_3_pressed() -> void:
	get_tree().change_scene_to_file("res://mapa/mapa.tscn")
	save_slot.visible = false
