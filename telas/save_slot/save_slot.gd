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
signal _lote_pronto

const MAX_SLOTS := 3

var slots: Array[Dictionary] = []
var ocupado := false          # evita cliques simultâneos (criar/apagar/carregar)

var _niveis_nome := {}        # nivel(int) -> descricao (catálogo, buscado uma vez)

var slot_carregado_normal = preload("res://assets/background/saveSlot.png")
var slot_carregado_hover = preload("res://assets/background/saveSlot.png")
var slot_carregado_pressed = preload("res://assets/background/saveSlot.png")

var slot_livre_normal = preload("res://assets/saveslot/normal.png")
var slot_livre_hover = preload("res://assets/saveslot/hover.png")
var slot_livre_pressed = preload("res://assets/saveslot/pressed.png")

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
	_limpar_slots()            # emite -> botões começam como "livres"
	carregar_saves()


func _atualizar_botoes(lista: Array) -> void:
	for i in range(mini(buttons.size(), lista.size())):
		if lista[i].vazio:
			buttons[i].texture_normal = slot_livre_normal
			buttons[i].texture_hover = slot_livre_hover
			buttons[i].texture_pressed = slot_livre_pressed
		else:
			buttons[i].texture_normal = slot_carregado_normal
			buttons[i].texture_hover = slot_carregado_hover
			buttons[i].texture_pressed = slot_carregado_pressed


# ==================== API pública ====================

## Busca os saves da conta + resumo de cada aeroporto e preenche `slots`.
func carregar_saves() -> bool:
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
	var ok := await _buscar_saves()
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
	var r := await GameApi.apagar_save(s.save_id)
	var ok: bool = r.ok and not (r.data is Array and (r.data as Array).is_empty())
	if not r.ok:
		_falhar(r.error)
	elif not ok:
		_falhar("Não foi possível apagar o save.")
	else:
		# Não deixa o GameState apontando para um aeroporto que não existe mais.
		if GameState.aeroporto_id == s.aeroporto_id:
			GameState.limpar()
		save_apagado.emit(numero)
		await _buscar_saves()
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
	var r := await GameApi.criar_save(numero)
	if not r.ok:
		_falhar(r.error)
		return ""
	var aeroporto_id := str(r.data)
	if not await _buscar_saves():
		return ""
	save_criado.emit(numero)
	return aeroporto_id


func _selecionar(numero: int) -> bool:
	var s := slot(numero)
	if s.is_empty() or s.vazio:
		_falhar("Esse slot está vazio.")
		return false
	var r := await GameState.carregar(s.aeroporto_id)
	if not r.ok:
		_falhar("Falha ao carregar o save: " + r.error)
		return false
	jogo_carregado.emit(s.aeroporto_id)
	return true


func _buscar_saves() -> bool:
	var r := await GameApi.listar_saves()
	if not r.ok:
		_falhar(r.error)
		return false

	var saves: Array = r.data if r.data is Array else []
	var ids: Array = []
	for s in saves:
		var a := _aeroporto_de(s)
		if not a.is_empty():
			ids.append(str(a.id))

	# Detalhes (respostas, aluguéis, minigames, catálogo de níveis) em paralelo.
	var respostas := {}
	var alugueis := {}
	var minigames := {}
	if not ids.is_empty():
		var chamadas: Array = [
			func(): return await GameApi.get_respostas_de(ids),
			func(): return await GameApi.get_alugueis_de(ids),
			func(): return await GameApi.get_minigames_de(ids),
		]
		if _niveis_nome.is_empty():
			chamadas.append(func(): return await GameApi.get_niveis())
		var res := await _em_paralelo(chamadas)
		# Os detalhes são secundários: se algum falhar, os saves ainda aparecem
		# (com esse campo zerado) e o erro é reportado, em vez de esconder tudo.
		for item in res:
			if not item.ok:
				_falhar("Detalhes do save indisponíveis: " + item.error)
		if res[0].ok:
			respostas = _agrupar_respostas(res[0].data)
		if res[1].ok:
			alugueis = _contar_por_aeroporto(res[1].data)
		if res[2].ok:
			minigames = _agrupar_minigames(res[2].data)
		if res.size() > 3 and res[3].ok:
			for n in res[3].data:
				_niveis_nome[int(n.id)] = str(n.get("descricao", ""))

	_limpar_slots(false)
	for s in saves:
		var numero := int(s.get("numero_slot", 0))
		var a := _aeroporto_de(s)
		if numero < 1 or numero > MAX_SLOTS:
			_falhar("Save com numero_slot inválido: %s" % str(s.get("numero_slot")))
			continue
		if a.is_empty():
			_falhar("Save do slot %d veio sem aeroporto (RLS na tabela aeroporto?)." % numero)
			continue
		var aid := str(a.id)
		var nivel := int(a.get("nivel_aeroporto_id", 1))
		var resp: Dictionary = respostas.get(aid, {"respondidas": 0, "acertadas": 0})
		slots[numero - 1] = {
			"numero": numero,
			"vazio": false,
			"save_id": str(s.id),
			"aeroporto_id": aid,
			"data_modificado": str(s.get("data_modificado", "")),
			"nivel": nivel,
			"nivel_nome": _niveis_nome.get(nivel, ""),
			"dinheiro": float(a.get("dinheiro", 0.0)),
			"fluxo_passageiros": float(a.get("fluxo_passageiros", 0.0)),
			"questoes_respondidas": resp.respondidas,
			"questoes_acertadas": resp.acertadas,
			"alugueis": alugueis.get(aid, 0),
			"minigames": minigames.get(aid, {}),
		}
	slots_atualizados.emit(slots)
	return true


## O embed pode vir como objeto (relação 1:1) ou lista (1:N); aceita os dois.
func _aeroporto_de(save: Dictionary) -> Dictionary:
	var a: Variant = save.get("aeroporto")
	if a is Array:
		return a[0] if not (a as Array).is_empty() else {}
	return a if a is Dictionary else {}


## aeroporto_id -> {respondidas, acertadas} (conta questões distintas).
func _agrupar_respostas(linhas: Array) -> Dictionary:
	var vistas := {}   # aeroporto_id -> {respondidas:{qid:true}, acertadas:{qid:true}}
	for l in linhas:
		var aid := str(l.aeroporto_id)
		var qid := int(l.questao_id)
		if not vistas.has(aid):
			vistas[aid] = {"respondidas": {}, "acertadas": {}}
		vistas[aid].respondidas[qid] = true
		if l.get("acertou", false):
			vistas[aid].acertadas[qid] = true
	var out := {}
	for aid in vistas:
		out[aid] = {
			"respondidas": vistas[aid].respondidas.size(),
			"acertadas": vistas[aid].acertadas.size(),
		}
	return out


func _contar_por_aeroporto(linhas: Array) -> Dictionary:
	var out := {}
	for l in linhas:
		var aid := str(l.aeroporto_id)
		out[aid] = int(out.get(aid, 0)) + 1
	return out


func _agrupar_minigames(linhas: Array) -> Dictionary:
	var out := {}
	for l in linhas:
		var aid := str(l.aeroporto_id)
		if not out.has(aid):
			out[aid] = {}
		out[aid][int(l.tipo_minigame_id)] = float(l.high_score)
	return out


## Roda várias chamadas assíncronas ao mesmo tempo e devolve os resultados na ordem.
func _em_paralelo(chamadas: Array) -> Array:
	var resultados: Array = []
	resultados.resize(chamadas.size())
	var estado := {"pendentes": chamadas.size()}
	for i in chamadas.size():
		_executar(chamadas[i], i, resultados, estado)
	if estado.pendentes > 0:
		await _lote_pronto
	return resultados


func _executar(chamada: Callable, i: int, resultados: Array, estado: Dictionary) -> void:
	resultados[i] = await chamada.call()
	estado.pendentes -= 1
	if estado.pendentes == 0:
		_lote_pronto.emit()


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
		_limpar_slots()
		GameState.limpar()
