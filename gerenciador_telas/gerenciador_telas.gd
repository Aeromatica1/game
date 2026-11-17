
extends Node

@onready var cadastro: Control = $Cadastro
@onready var login: Control = $Login
@onready var menu_principal: Control = $MenuPrincipal
@onready var save_slot: TelaSaveSlot = $SaveSlot
@onready var barra_usuario: CanvasLayer = $BarraUsuario
@onready var botao_voltar: Button = $BarraUsuario/Voltar

var cena_atual: Control
var historico_cenas: Array[Control] = []


func _ready() -> void:
	Supabase.restore_session()

	# Estado inicial
	for cena in [cadastro, login, menu_principal, save_slot]:
		cena.visible = false

	# Voltando do mapa: reconstrói o histórico guardado; senão começa no menu.
	if not _restaurar_historico(Navegacao.consumir_historico()):
		cena_atual = menu_principal
		historico_cenas.append(cena_atual)

	cena_atual.visible = true
	botao_voltar.visible = historico_cenas.size() > 1

	login.login_sucesso.connect(_on_login_sucesso)
	cadastro.cadastro_sucesso.connect(_on_cadastro_sucesso)
	save_slot.jogo_carregado.connect(_on_jogo_carregado)

	if cena_atual == save_slot:
		save_slot.carregar_saves()


## Histórico como nomes de nós (formato que sobrevive à troca de cena).
func _nomes_historico() -> Array[String]:
	var nomes: Array[String] = []
	for c in historico_cenas:
		nomes.append(String(c.name))
	return nomes


func _restaurar_historico(nomes: Array[String]) -> bool:
	var validas: Array = [cadastro, login, menu_principal, save_slot]
	var lista: Array[Control] = []
	for n in nomes:
		var c := get_node_or_null(n) as Control
		if c != null and validas.has(c):
			lista.append(c)
	if lista.is_empty():
		return false
	historico_cenas = lista
	cena_atual = lista.back()
	return true


# ==================== Navegação ====================

func _trocar_para(cena_nova: Control) -> void:
	if cena_nova == cena_atual:
		return

	cena_atual.visible = false
	cena_nova.visible = true

	cena_atual = cena_nova
	historico_cenas.append(cena_atual)

	botao_voltar.visible = historico_cenas.size() > 1

	if cena_atual == save_slot:
		save_slot.carregar_saves()


func _retornar() -> void:
	if historico_cenas.size() <= 1:
		return
		
	historico_cenas.pop_back()
	var cena_anterior: Control = historico_cenas.back()

	cena_atual.visible = false
	cena_anterior.visible = true

	cena_atual = cena_anterior

	botao_voltar.visible = historico_cenas.size() > 1

	if cena_atual == save_slot:
		save_slot.carregar_saves()


# ==================== Menu Principal ====================

func _on_botao_jogar_pressed() -> void:
	# A sessão salva é restaurada de forma assíncrona: espera antes de mandar para o login.
	if not Supabase.is_logged_in():
		await Supabase.restore_session()
	if Supabase.is_logged_in():
		_trocar_para(save_slot)
	else:
		_trocar_para(login)


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

func _on_slot_1_pressed() -> void:
	save_slot.abrir_slot(1)

func _on_slot_2_pressed() -> void:
	save_slot.abrir_slot(2)

func _on_slot_3_pressed() -> void:
	save_slot.abrir_slot(3)

func _on_jogo_carregado(_aeroporto_id: String) -> void:
	# O gerenciador será destruído: o histórico vai para o autoload Navegacao.
	Navegacao.ir_para_mapa(_nomes_historico())


func _on_voltar_pressed() -> void:
	_retornar()
