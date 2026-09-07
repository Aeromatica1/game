extends Node

@onready var cadastro: Control = $Cadastro
@onready var login: Control = $Login

func _on_registrar_botao_pressed() -> void:
	login.visible = false
	cadastro.visible = true

func _on_logar_botao_pressed() -> void:
	cadastro.visible = false
	login.visible = true
	
func _ready() -> void:
	cadastro.visible = false
	login.visible = true
