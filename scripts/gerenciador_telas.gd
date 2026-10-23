extends Node

@onready var cadastro: Control = $Cadastro
@onready var login: Control = $Login
@onready var menu_principal: Control = $MenuPrincipal
@onready var save_slot: Control = $SaveSlot


# ==================== Menu Principal ====================

func _ready() -> void:
	menu_principal.visible = true
	login.visible = false
	cadastro.visible = false
	save_slot.visible = false

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
	menu_principal.visible = true
	save_slot.visible = false

func _on_add_2_pressed() -> void:
	menu_principal.visible = true
	save_slot.visible = false

func _on_add_3_pressed() -> void:
	menu_principal.visible = true
	save_slot.visible = false
