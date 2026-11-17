class_name TelaSaveSlot
extends Control
## Lógica da cena SaveSlot (sem interface).
##
## A tela de UI só precisa:
##   - chamar `carregar_saves()` ao exibir a cena;
##   - ler `slots` / ouvir `slots_atualizados` para desenhar os 3 botões;
##   - chamar `abrir_slot(n)`, `criar_save(n)` ou `apagar_save(n)` nos botões.
##
## Cada item de `slots` (sempre MAX_SLOTS itens, índice = numero - 1):
##   {
##     numero: int, vazio: bool,
##     save_id: String, aeroporto_id: String, data_modificado: String,
##     nivel: int, nivel_nome: String,
##     dinheiro: float, fluxo_passageiros: float,
##     questoes_respondidas: int, questoes_acertadas: int,
##     alugueis: int,
##     minigames: Dictionary   # tipo_minigame_id(int) -> high_score(float)
##   }
## Em slot vazio só `numero` e `vazio` (true) são relevantes.



signal carregando_mudou(carregando: bool)
signal slots_atualizados(slots: Array)
signal save_criado(numero: int)
signal save_apagado(numero: int)
## Save escolhido e já carregado no GameState; o gerenciador troca para o mapa.
signal jogo_carregado(aeroporto_id: String)
signal erro(mensagem: String)
## Não há sessão (nem salva) -> a UI/gerenciador pode mandar para o login.
signal login_necessario

const MAX_SLOTS := 3

var slots: Array[Dictionary] = []
var ocupado := false          # evita cliques simultâneos (criar/apagar/carregar)


var slot_ocupado_normal = preload("res://assets/saveslot/ocupado_normal.png")
var slot_ocupado_hover = preload("res://assets/saveslot/ocupado_hover.png")
var slot_ocupado_pressed = preload("res://assets/saveslot/ocupado_pressed.png")

var slot_livre_normal = preload("res://assets/saveslot/livre_normal.png")
var slot_livre_hover = preload("res://assets/saveslot/livre_hover.png")
var slot_livre_pressed = preload("res://assets/saveslot/livre_pressed.png")

@onready var buttons: Array[TextureButton] = [
	$AreaSlots/Slot1,
	$AreaSlots/Slot2,
	$AreaSlots/Slot3
]

func _ready() -> void:
	# Os botões são redesenhados SEMPRE que `slots` muda (os dados chegam depois,
	# de forma assíncrona; antes eram desenhados uma única vez, ainda vazios).
	slots_atualizados.connect(_atualizar_botoes)
	Supabase.session_changed.connect(_on_session_changed)
	if GameState.conta_pronta:
		_publicar_slots()      # já em cache: desenha na hora
	else:
		_limpar_slots()        # emite -> botões começam como "livres"
	carregar_saves()


func _atualizar_botoes(lista: Array) -> void:
	for i in range(mini(buttons.size(), lista.size())):
		if lista[i].vazio:
			buttons[i].get_node("Informacoes").visible = false
			buttons[i].texture_normal = slot_livre_normal
			buttons[i].texture_hover = slot_livre_hover
			buttons[i].texture_pressed = slot_livre_pressed
		else:
			buttons[i].get_node("Informacoes").visible = true
			buttons[i].texture_normal = slot_ocupado_normal
			buttons[i].texture_hover = slot_ocupado_hover
			buttons[i].texture_pressed = slot_ocupado_pressed


# ==================== API pública ====================

## Preenche `slots` a partir do GameState (a conta é baixada uma vez, no login).
## `forcar` = rebaixa tudo do servidor.
func carregar_saves(forcar := false) -> bool:
	if ocupado:
		return false
	_set_ocupado(true)
	# A sessão é restaurada de forma assíncrona (user://session.cfg): no início do jogo
	# `is_logged_in()` ainda é falso mesmo com login salvo. Espera a restauração antes de decidir.
	if not Supabase.is_logged_in():
		await Supabase.restore_session()
	if not Supabase.is_logged_in():
		_limpar_slots()
		_set_ocupado(false)
		login_necessario.emit()
		return false
	var ok := await _atualizar_slots(forcar)
	_set_ocupado(false)
	return ok


## Cria um save no slot vazio `numero` (1..MAX_SLOTS).
func criar_save(numero: int) -> bool:
	if ocupado:
		return false
	_set_ocupado(true)
	var aeroporto_id := await _criar(numero)
	_set_ocupado(false)
	return aeroporto_id != ""


## Apaga o save do slot `numero`.
func apagar_save(numero: int) -> bool:
	if ocupado:
		return false
	var s := slot(numero)
	if s.is_empty() or s.vazio:
		_falhar("Esse slot já está vazio.")
		return false
	_set_ocupado(true)
	var r = await GameApi.apagar_save(s.save_id)
	var ok: bool = r.ok and not (r.data is Array and (r.data as Array).is_empty())
	if not r.ok:
		_falhar(r.error)
	elif not ok:
		_falhar("Não foi possível apagar o save.")
	else:
		GameState.remover_save(s.save_id)   # tira do cache (e esquece o save se estava aberto)
		_publicar_slots()
		save_apagado.emit(numero)
	_set_ocupado(false)
	return ok


## Carrega o save do slot no GameState (uma requisição) e emite `jogo_carregado`.
func selecionar_save(numero: int) -> bool:
	if ocupado:
		return false
	_set_ocupado(true)
	var ok := await _selecionar(numero)
	_set_ocupado(false)
	return ok


## Ação do botão do slot: se vazio cria o save e entra; se ocupado, entra.
func abrir_slot(numero: int) -> bool:
	if ocupado:
		return false
	_set_ocupado(true)
	var s := slot(numero)
	var ok := true
	if not s.is_empty() and s.vazio:
		ok = await _criar(numero) != ""
	if ok:
		ok = await _selecionar(numero)
	_set_ocupado(false)
	return ok


## Dados do slot `numero` ({} se número inválido).
func slot(numero: int) -> Dictionary:
	if numero < 1 or numero > slots.size():
		return {}
	return slots[numero - 1]


func proximo_slot_livre() -> int:
	for s in slots:
		if s.vazio:
			return s.numero
	return 0


# ==================== Internos ====================

func _criar(numero: int) -> String:
	if numero < 1 or numero > MAX_SLOTS:
		_falhar("Slot inválido.")
		return ""
	var s := slot(numero)
	if not s.is_empty() and not s.vazio:
		_falhar("Esse slot já tem um save.")
		return ""
	var r = await GameApi.criar_save(numero)
	if not r.ok:
		_falhar(r.error)
		return ""
	var aeroporto_id := str(r.data)
	# Só o save novo é baixado; os outros já estão em cache.
	var rr = await GameState.recarregar_saves()
	if not rr.ok:
		_falhar(rr.error)
		return ""
	_avisar(rr)
	_publicar_slots()
	save_criado.emit(numero)
	return aeroporto_id


func _selecionar(numero: int) -> bool:
	var s := slot(numero)
	if s.is_empty() or s.vazio:
		_falhar("Esse slot está vazio.")
		return false
	var r = await GameState.carregar(s.aeroporto_id)
	if not r.ok:
		_falhar("Falha ao carregar o save: " + r.error)
		return false
	jogo_carregado.emit(s.aeroporto_id)
	return true


## Garante a conta no GameState (pré-carregada no login; sem rede se já estiver pronta)
## e desenha os slots a partir do cache.
func _atualizar_slots(forcar := false) -> bool:
	var r = await GameState.carregar_conta(forcar)
	if not r.ok:
		_falhar(r.error)
		return false
	_avisar(r)
	_publicar_slots()
	return true


func _publicar_slots() -> void:
	slots = GameState.resumo_slots(MAX_SLOTS)
	slots_atualizados.emit(slots)


func _avisar(resultado: Dictionary) -> void:
	for aviso in resultado.get("avisos", []):
		_falhar(str(aviso))


func _limpar_slots(emitir := true) -> void:
	slots.clear()
	for n in range(1, MAX_SLOTS + 1):
		slots.append({"numero": n, "vazio": true})
	if emitir:
		slots_atualizados.emit(slots)


func _set_ocupado(v: bool) -> void:
	ocupado = v
	carregando_mudou.emit(v)


func _falhar(mensagem: String) -> void:
	push_warning("[SaveSlot] " + mensagem)
	print("[SaveSlot] ", mensagem)      # também no painel Output
	erro.emit(mensagem)


func _on_session_changed(logado: bool) -> void:
	if not logado:
		_limpar_slots()            # o GameState se limpa sozinho no logout
