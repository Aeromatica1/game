extends Node

## Autoload "GameState": cache em memória de TUDO do jogador, exceto questões/alternativas.
##
## Fluxo:
##  1) Ao logar (Supabase.session_changed), `carregar_conta()` baixa de uma vez: usuário, catálogos
##     (níveis, tipos de aluguel, tipos de minigame) e todos os saves com respostas, aluguéis e
##     minigames. As telas (ex.: SaveSlot) só LEEM daqui, sem rede.
##  2) Ao escolher um save, `carregar()` baixa as questões (+ alternativas) e refresca esse save.
##  3) Ações que mudam dinheiro/progresso (responder, evoluir...) vão ao servidor, que valida;
##     o resultado é aplicado no cache. O servidor continua sendo a fonte da verdade.
##
## Os dados do save atual (`aeroporto`, `concluidas`, `alugueis`, `minigames`) são REFERÊNCIAS
## para o cache da conta: alterar um altera o outro, então os resumos dos slots nunca divergem.
## Por isso nunca use `.clear()` neles fora de `_atualizar_save` e `reiniciar_progresso`; para "esquecer" o save use `limpar()`.

signal conta_carregada               # terminou (com ou sem sucesso) um carregar_conta()
signal carregado                     # save atual carregado (questões prontas)
signal dinheiro_mudou(valor: float)
signal nivel_mudou(nivel: int)
signal aluguel_feito(numero_area: int)
signal evoluiu(novo_nivel: int)                # só quando o jogador sobe de nível (não no reset)
signal game_over(motivo: String)
signal progresso_reiniciado(ok: bool)
signal _questoes_baixadas

# ------------------------- Conta (carregada no login) -------------------------
var conta_pronta := false
var usuario := {}                   # linha de profiles (id, username, created_at) + email
var niveis := {}                    # nivel(int) -> {id, descricao, recompensa, dinheiro_necessario, questoes_necessarias}
var tipos_aluguel: Array = []
var tipos_minigame: Array = []
var saves: Array = []               # linhas de save_slot (+ "aeroporto_id"), sem o embed do aeroporto
var _dados := {}                    # aeroporto_id -> {aeroporto, respostas, concluidas, alugueis, minigames}

# ------------------------- Save atual (referências para _dados[aeroporto_id]) -------------------------
var aeroporto_id := ""
var aeroporto := {}                 # todas as colunas de aeroporto (id, nivel_aeroporto_id, dinheiro, fluxo_passageiros...)
var respostas := {}                 # questao_id(int) -> acertou(bool); 1 linha por questão (aeroporto_resposta)
var concluidas := {}                # questao_id(int) -> true (só as acertadas)
var alugueis: Array = []
var minigames := {}                 # tipo_minigame_id(int) -> high_score
# Só o save atual (carregadas em carregar(); não entram no pré-carregamento da conta):
var questoes: Array[Dictionary] = []  # {id, nivel, enunciado, recompensa, alternativas:[{id, enunciado}]}

var _catalogo_questoes: Array[Dictionary] = []   # todas as questões (iguais para todos os saves)
var _carregando_questoes := false
var game_over_ativo := false        # entre o game over e o jogador escolher reiniciar/menu
var reset_ok := false               # o reset do save (servidor) do game over foi concluído
var reset_erro := ""
var _resetando := false
var _evoluindo := false
var _ultima_sorteada := -1
var _vistas := {}                   # questões já sorteadas neste ciclo (para nunca repetir enquanto houver outras)
var _carregando_conta := false
var _resultado_conta := {}


class _Lote extends RefCounted:
	signal pronto
	var pendentes := 0
	var resultados: Array = []


func _ready() -> void:
	Supabase.session_changed.connect(_ao_mudar_sessao)


func _ao_mudar_sessao(logado: bool) -> void:
	if logado:
		carregar_conta()             # em segundo plano: roda enquanto o jogador está no menu/login
	else:
		limpar_conta()


# JSON do Godot devolve todo número como float; normalizamos ids para int
# (se mandar 1.0 de volta, o Postgres rejeita "1.0" como integer).
static func _i(v: Variant) -> int:
	return int(v)


static func _falha(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "avisos": []}


# ========================= Conta =========================

## Baixa tudo da conta (menos questões). Sem rede se já estiver carregada (use `forcar` para refazer).
## Retorna {ok, error, avisos}; `avisos` = problemas não fatais (ex.: detalhe de um save indisponível).
func carregar_conta(forcar := false) -> Dictionary:
	if not Supabase.is_logged_in():
		return _falha("Sem sessão ativa.")
	if _carregando_conta:
		await conta_carregada
		return _resultado_conta
	if conta_pronta and not forcar and usuario.get("id", "") == Supabase.user_id:
		return {"ok": true, "avisos": []}
	_carregando_conta = true
	_resultado_conta = await _baixar_conta()
	_carregando_conta = false
	conta_carregada.emit()
	return _resultado_conta


func _baixar_conta() -> Dictionary:
	var res := await _em_paralelo([
		func(): return await GameApi.get_niveis(),
		func(): return await GameApi.get_tipos_aluguel(),
		func(): return await GameApi.get_tipos_minigame(),
		func(): return await _buscar_saves(),
		func(): return await GameApi.get_perfil(Supabase.user_id),
	])
	var avisos := []
	for i in 4:
		if not res[i].ok:
			return _falha(res[i].error)
	# Perfil é secundário: se falhar, usa o username que veio no login (user_metadata).
	var perfil: Dictionary = {}
	if res[4].ok and res[4].data is Array and not (res[4].data as Array).is_empty():
		perfil = res[4].data[0]
	else:
		avisos.append("Perfil indisponível: " + (res[4].error if not res[4].ok else "linha de profiles não encontrada"))

	niveis.clear()
	for n in _como_lista(res[0].data):
		n["id"] = _i(n.id)
		niveis[n.id] = n
	tipos_aluguel = _como_lista(res[1].data)
	tipos_minigame = _como_lista(res[2].data)
	usuario = perfil.duplicate()
	usuario["id"] = Supabase.user_id
	usuario["email"] = Supabase.email
	if str(usuario.get("username", "")) == "":
		usuario["username"] = Supabase.username

	_dados.clear()
	avisos.append_array(await _aplicar_saves(_como_lista(res[3].data), false))
	conta_pronta = true
	_pre_carregar_questoes()        # em segundo plano: entrar no save passa a não depender da rede
	# Recarga forçada com um save aberto: reaponta para os dados novos (ou esquece se sumiu).
	if aeroporto_id != "":
		if _dados.has(aeroporto_id):
			_apontar(aeroporto_id)
		else:
			limpar()
	return {"ok": true, "avisos": avisos}


## Rebusca só a lista de saves (ex.: depois de criar um). Saves já em cache não são rebaixados.
func recarregar_saves() -> Dictionary:
	var r = await _buscar_saves()
	if not r.ok:
		return _falha(r.error)
	var avisos := await _aplicar_saves(_como_lista(r.data), true)
	_pre_carregar_questoes()        # usuário novo: agora há um aeroporto para buscar as questões
	return {"ok": true, "avisos": avisos}


## Tira um save apagado do cache (o servidor já apagou).
func remover_save(save_id: String) -> void:
	for i in saves.size():
		if str(saves[i].id) == save_id:
			var aid: String = saves[i].aeroporto_id
			saves.remove_at(i)
			_dados.erase(aid)
			if aeroporto_id == aid:
				limpar()
			return


## Esquece a conta inteira (logout).
func limpar_conta() -> void:
	conta_pronta = false
	usuario = {}
	niveis = {}
	tipos_aluguel = []
	tipos_minigame = []
	saves = []
	_dados = {}
	_catalogo_questoes = []
	limpar()


## Esquece só o save aberto (a conta continua em cache). Cria contêineres novos em vez de
## `.clear()`, para não esvaziar os dados que o cache da conta ainda guarda.
func limpar() -> void:
	aeroporto_id = ""
	aeroporto = {}
	respostas = {}
	concluidas = {}
	alugueis = []
	minigames = {}
	questoes.clear()
	_ultima_sorteada = -1
	_vistas = {}
	game_over_ativo = false
	reset_ok = false


## Resumo dos `max_slots` slots para a tela de saves (índice = numero - 1).
## Slot vazio: só {numero, vazio:true}.
func resumo_slots(max_slots := 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in range(1, max_slots + 1):
		out.append({"numero": n, "vazio": true})
	for s in saves:
		var n := _i(s.get("numero_slot", 0))
		if n < 1 or n > max_slots:
			push_warning("[GameState] Save com numero_slot inválido: %s" % str(s.get("numero_slot")))
			continue
		var e: Dictionary = _dados.get(s.aeroporto_id, {})
		if e.is_empty():
			continue
		var a: Dictionary = e.aeroporto
		var nivel := _i(a.get("nivel_aeroporto_id", 1))
		out[n - 1] = {
			"numero": n,
			"vazio": false,
			"save_id": str(s.id),
			"aeroporto_id": str(s.aeroporto_id),
			"data_modificado": str(s.get("data_modificado", "")),
			"nivel": nivel,
			"nivel_nome": str(niveis.get(nivel, {}).get("descricao", "")),
			"dinheiro": float(a.get("dinheiro", 0.0)),
			"fluxo_passageiros": float(a.get("fluxo_passageiros", 0.0)),
			"questoes_respondidas": e.respostas.size(),
			"questoes_acertadas": e.concluidas.size(),
			"alugueis": e.alugueis.size(),
			"minigames": e.minigames,
		}
	return out


## Uma requisição só (saves + aeroporto + respostas + aluguéis + minigames). Se o embed aninhado
## falhar por algum motivo, cai para a lista simples e os detalhes são buscados depois.
func _buscar_saves() -> Dictionary:
	var r = await GameApi.listar_saves_completo()
	if r.ok:
		return r
	push_warning("[GameState] Embed completo dos saves falhou (%s); usando busca em etapas." % r.error)
	return await GameApi.listar_saves()


# Monta `saves` e `_dados` a partir das linhas de save_slot (com aeroporto embutido). Se os detalhes
# (respostas/aluguéis/minigames) não vierem embutidos, baixa em paralelo. Retorna avisos não fatais.
func _aplicar_saves(linhas: Array, so_novos: bool) -> Array:
	var avisos := []
	var novos_saves := []
	var aeroportos := {}              # aeroporto_id -> linha de aeroporto
	var precisam: Array = []          # ids que ganham uma entrada nova no cache
	var buscar: Array = []            # ids cujos detalhes NÃO vieram embutidos
	var resp_por: Dictionary = {}
	var alug_por: Dictionary = {}
	var mini_por: Dictionary = {}
	for s in linhas:
		var numero := _i(s.get("numero_slot", 0))
		var a := _aeroporto_de(s)
		if a.is_empty():
			avisos.append("Save do slot %d veio sem aeroporto (RLS na tabela aeroporto?)." % numero)
			continue
		var aid := str(a.id)
		var linha: Dictionary = s.duplicate()
		linha.erase("aeroporto")
		linha["aeroporto_id"] = aid
		linha["numero_slot"] = numero
		novos_saves.append(linha)
		aeroportos[aid] = a
		var embutido := a.has("aeroporto_resposta") and a.has("aluguel_localizacao") and a.has("minigame_aeroporto")
		if embutido:
			_acumular(_como_lista(a.aeroporto_resposta), _como_lista(a.aluguel_localizacao),
				_como_lista(a.minigame_aeroporto), resp_por, alug_por, mini_por)
		for k in ["aeroporto_resposta", "aluguel_localizacao", "minigame_aeroporto"]:
			a.erase(k)
		if not (so_novos and _dados.has(aid)):
			precisam.append(aid)
			if not embutido:
				buscar.append(aid)
	saves = novos_saves
	for aid in _dados.keys():
		if not aeroportos.has(aid):
			_dados.erase(aid)

	if not buscar.is_empty():
		var res := await _em_paralelo([
			func(): return await GameApi.get_respostas_de(buscar),
			func(): return await GameApi.get_alugueis_de(buscar),
			func(): return await GameApi.get_minigames_de(buscar),
		])
		# Detalhes são secundários: se falharem, os saves ainda aparecem (com esse campo zerado).
		for item in res:
			if not item.ok:
				avisos.append("Detalhes do save indisponíveis: " + item.error)
		_acumular(_como_lista(res[0].data) if res[0].ok else [], _como_lista(res[1].data) if res[1].ok else [],
			_como_lista(res[2].data) if res[2].ok else [], resp_por, alug_por, mini_por)

	for aid in precisam:
		var a: Dictionary = aeroportos[aid]
		a["nivel_aeroporto_id"] = _i(a.get("nivel_aeroporto_id", 1))
		var resp: Dictionary = resp_por.get(aid, {})
		var conc := {}
		for qid in resp:
			if resp[qid]:
				conc[qid] = true
		_dados[aid] = {
			"aeroporto": a,
			"respostas": resp,
			"concluidas": conc,
			"alugueis": alug_por.get(aid, []),
			"minigames": mini_por.get(aid, {}),
		}
	return avisos


# Agrupa linhas de aeroporto_resposta / aluguel_localizacao / minigame_aeroporto por aeroporto_id.
func _acumular(respostas_l: Array, alugueis_l: Array, minigames_l: Array,
		resp_por: Dictionary, alug_por: Dictionary, mini_por: Dictionary) -> void:
	for l in respostas_l:
		var aid := str(l.aeroporto_id)
		if not resp_por.has(aid):
			resp_por[aid] = {}
		resp_por[aid][_i(l.questao_id)] = bool(l.get("acertou", false))
	for l in alugueis_l:
		var aid := str(l.aeroporto_id)
		if not alug_por.has(aid):
			alug_por[aid] = []
		alug_por[aid].append(l)
	for l in minigames_l:
		var aid := str(l.aeroporto_id)
		if not mini_por.has(aid):
			mini_por[aid] = {}
		mini_por[aid][_i(l.tipo_minigame_id)] = float(l.high_score)


## O embed pode vir como objeto (relação 1:1) ou lista (1:N); aceita os dois.
func _aeroporto_de(save: Dictionary) -> Dictionary:
	var a: Variant = save.get("aeroporto")
	if a is Array:
		return a[0] if not (a as Array).is_empty() else {}
	return a if a is Dictionary else {}


static func _como_lista(v: Variant) -> Array:
	return v if v is Array else []


## Roda várias chamadas assíncronas ao mesmo tempo e devolve os resultados na ordem.
func _em_paralelo(chamadas: Array) -> Array:
	var lote := _Lote.new()
	lote.pendentes = chamadas.size()
	lote.resultados.resize(chamadas.size())
	for i in chamadas.size():
		_executar(chamadas[i], i, lote)
	if lote.pendentes > 0:
		await lote.pronto
	return lote.resultados


func _executar(chamada: Callable, i: int, lote: _Lote) -> void:
	lote.resultados[i] = await chamada.call()
	lote.pendentes -= 1
	if lote.pendentes == 0:
		lote.pronto.emit()


# ========================= Save atual =========================

## Escolhe o save. Com a conta e as questões já em cache (pré-carregadas em segundo plano
## depois do login) não usa a rede: é instantâneo. Se as questões não estiverem em cache
## (ex.: usuário novo), baixa via carregar_jogo e já guarda para os próximos saves.
func carregar(p_aeroporto_id: String) -> Dictionary:
	if not conta_pronta:
		var c := await carregar_conta()
		if not c.ok:
			return c
	if _carregando_questoes:
		await _questoes_baixadas

	if _dados.has(p_aeroporto_id):
		_apontar(p_aeroporto_id)
		if _catalogo_tem_nivel(nivel_atual()):
			_usar_catalogo()
			return {"ok": true, "data": null, "error": ""}

	# Caminho lento: o servidor devolve o save atualizado + questões.
	var r = await GameApi.carregar_jogo(p_aeroporto_id)
	if not r.ok:
		return r
	var d: Dictionary = r.data
	_atualizar_save(p_aeroporto_id, d)
	var baixadas := _normalizar_questoes(d.get("questoes", []))
	if not baixadas.is_empty():
		_catalogo_questoes = baixadas
	_usar_catalogo()
	return r


func _usar_catalogo() -> void:
	questoes.assign(_catalogo_questoes)
	_ultima_sorteada = -1
	_vistas = {}
	carregado.emit()


func _catalogo_tem_nivel(nivel: int) -> bool:
	for q in _catalogo_questoes:
		if q.nivel == nivel:
			return true
	return false


# JSON -> ids int e alternativas normalizadas.
func _normalizar_questoes(lista: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in lista:
		q["id"] = _i(q.id)
		q["nivel"] = _i(q.nivel)
		for a in q.alternativas:
			a["id"] = _i(a.id)
		out.append(q)
	return out


# As questões não dependem do save: uma chamada (com qualquer aeroporto da conta) serve a todos.
func _pre_carregar_questoes() -> void:
	if _carregando_questoes or not _catalogo_questoes.is_empty() or saves.is_empty():
		return
	_carregando_questoes = true
	var r = await GameApi.carregar_jogo(str(saves[0].aeroporto_id))
	if r.ok and r.data is Dictionary:
		_catalogo_questoes = _normalizar_questoes(r.data.get("questoes", []))
	_carregando_questoes = false
	_questoes_baixadas.emit()


# Refresca, no cache, o save com o que o servidor devolveu (atualiza no lugar, mantém referências).
func _atualizar_save(aid: String, d: Dictionary) -> void:
	var e: Dictionary = _dados.get(aid, {})
	if e.is_empty():
		e = {"aeroporto": {}, "respostas": {}, "concluidas": {}, "alugueis": [], "minigames": {}}
		_dados[aid] = e
	e.aeroporto.merge(d.get("aeroporto", {}), true)
	e.aeroporto["nivel_aeroporto_id"] = _i(e.aeroporto.get("nivel_aeroporto_id", 1))
	e.concluidas.clear()
	for qid in d.get("questoes_concluidas", []):
		e.concluidas[_i(qid)] = true
		e.respostas[_i(qid)] = true      # respostas erradas já em cache são mantidas
	e["alugueis"] = d.get("alugueis", [])
	e.minigames.clear()
	for m in d.get("minigames", []):
		e.minigames[_i(m.tipo_minigame_id)] = float(m.high_score)
	_apontar(aid)


func _apontar(aid: String) -> void:
	var e: Dictionary = _dados[aid]
	aeroporto_id = aid
	aeroporto = e.aeroporto
	respostas = e.respostas
	concluidas = e.concluidas
	alugueis = e.alugueis
	minigames = e.minigames


# ------------------------- Leitura do estado -------------------------
func nivel_atual() -> int:
	return _i(aeroporto.get("nivel_aeroporto_id", 1))

func dinheiro() -> float:
	return float(aeroporto.get("dinheiro", 0.0))

## Fluxo de passageiros do aeroporto (1 a 10; +3 a cada nível, calculado no servidor).
func fluxo() -> int:
	return _i(aeroporto.get("fluxo_passageiros", 1))

func username() -> String:
	return str(usuario.get("username", ""))

func questoes_do_nivel(nivel: int) -> Array:
	return questoes.filter(func(item): return item.nivel == nivel)

## Vector2i(acertos, total) das questões do nível atual.
func progresso_nivel() -> Vector2i:
	var lista := questoes_do_nivel(nivel_atual())
	var acertos := 0
	for item in lista:
		if concluidas.has(item.id):
			acertos += 1
	return Vector2i(acertos, lista.size())


# ------------------------- Sorteio (100% local) -------------------------
## Sorteia uma questão do nível atual que ainda não foi acertada, sem repetir nenhuma até todas
## as outras do nível terem saído (ciclo). Prefere as nunca respondidas: só há 1 resposta por
## questão por aeroporto, então as erradas só voltam quando não resta nenhuma inédita.
## Embaralha as alternativas. Retorna {} quando o nível acabou.
func sortear_questao() -> Dictionary:
	var base := questoes_do_nivel(nivel_atual()).filter(func(item): return not concluidas.has(item.id))
	if base.is_empty():
		return {}
	var pool := base.filter(func(item): return not respostas.has(item.id))
	if pool.is_empty():
		pool = base
	var novas := pool.filter(func(item): return not _vistas.has(item.id))
	if novas.is_empty():
		# Ciclo completo: recomeça, mas nunca devolve a questão que acabou de sair se houver outra.
		_vistas = {}
		novas = pool.filter(func(item): return item.id != _ultima_sorteada)
		if novas.is_empty():
			novas = pool
	var q: Dictionary = novas.pick_random().duplicate(true)
	var alts: Array = q.alternativas
	alts.shuffle()
	q.alternativas = alts
	_ultima_sorteada = q.id
	_vistas[q.id] = true
	return q


# ------------------------- Ações (validadas no servidor) -------------------------
## Envia a resposta; o servidor decide se acertou. Atualiza o cache com o resultado.
func responder(questao_id: int, alternativa_id: int) -> Dictionary:
	var r = await GameApi.responder_questao(aeroporto_id, questao_id, alternativa_id)
	if not r.ok:
		return r
	var d: Dictionary = r.data
	var antes := dinheiro()
	var acertou := bool(d.get("acertou", false))
	respostas[questao_id] = bool(respostas.get(questao_id, false)) or acertou
	if acertou:
		concluidas[questao_id] = true
	var novo := float(d.get("dinheiro", antes))
	d["variacao"] = snappedf(novo - antes, 0.01)   # + recompensa ao acertar, - perda ao errar
	_set_dinheiro(novo)
	# Evolução / game over são avaliados depois que a tela de questão mostra o resultado.
	call_deferred("_avaliar_progresso", acertou)
	return r


## Linha de aluguel_localizacao da área `numero_area` (1 a 27) ou {} se estiver livre.
func aluguel_da_area(numero_area: int) -> Dictionary:
	for l in alugueis:
		if _i(l.get("numero_area", 0)) == numero_area:
			return l
	return {}


## tipo_aluguel pelo id ({} se não existir).
func tipo_aluguel(id: int) -> Dictionary:
	for t in tipos_aluguel:
		if _i(t.id) == id:
			return t
	return {}


## Aluga a área no servidor (valida nível, preço e se a área está livre) e atualiza o cache.
func alugar(tipo_aluguel_id: int, numero_area: int) -> Dictionary:
	var r = await GameApi.alugar_espaco(aeroporto_id, tipo_aluguel_id, numero_area)
	if not r.ok:
		return r
	alugueis.append({
		"aeroporto_id": aeroporto_id,
		"tipo_aluguel_id": tipo_aluguel_id,
		"numero_area": numero_area,
	})
	# O servidor cobrou o preço: relê a linha do aeroporto para o dinheiro não divergir.
	var novo = await GameApi.get_aeroporto(aeroporto_id)
	if novo.ok and novo.data is Array and not novo.data.is_empty():
		aeroporto.merge(novo.data[0], true)
		aeroporto["nivel_aeroporto_id"] = _i(aeroporto.nivel_aeroporto_id)
		dinheiro_mudou.emit(dinheiro())
	aluguel_feito.emit(numero_area)
	call_deferred("_avaliar_progresso", false)       # pagar o aluguel pode zerar o dinheiro
	return r


func pode_evoluir() -> bool:
	var prox: Dictionary = niveis.get(nivel_atual() + 1, {})
	if prox.is_empty():
		return false
	return progresso_nivel().x >= _i(prox.questoes_necessarias) \
		and dinheiro() >= float(prox.dinheiro_necessario)


func evoluir() -> Dictionary:
	if _evoluindo:
		return {"ok": false, "error": "Evolução em andamento."}
	_evoluindo = true
	var r = await GameApi.evoluir_aeroporto(aeroporto_id)
	_evoluindo = false
	if r.ok:
		aeroporto["nivel_aeroporto_id"] = _i(r.data)
		# O servidor mexe em dinheiro (custo/recompensa do nível) e fluxo_passageiros (+3):
		# relemos a linha do aeroporto para o cache não divergir.
		var novo = await GameApi.get_aeroporto(aeroporto_id)
		if novo.ok and not novo.data.is_empty():
			aeroporto.merge(novo.data[0], true)
			aeroporto["nivel_aeroporto_id"] = _i(aeroporto.nivel_aeroporto_id)
			_set_dinheiro(float(aeroporto.get("dinheiro", 0.0)))
		nivel_mudou.emit(nivel_atual())
		evoluiu.emit(nivel_atual())
	return r


## Envia a pontuação de um minigame ao servidor (RPC `concluir_minigame`).
## O servidor guarda o recorde e credita o dinheiro; depois recarregamos só o dinheiro
## para o cache não divergir (a barra do aeroporto se atualiza sozinha pelo sinal).
func concluir_minigame(tipo_minigame_id_: int, score: float) -> Dictionary:
	if aeroporto_id == "":
		return {"ok": false, "code": 0, "data": null, "error": "Nenhum save carregado", "error_code": "no_save"}
	var r = await GameApi.concluir_minigame(aeroporto_id, tipo_minigame_id_, score)
	if not r.ok:
		return r
	if score > float(minigames.get(tipo_minigame_id_, 0.0)):
		minigames[tipo_minigame_id_] = score
	var novo = await GameApi.get_aeroporto(aeroporto_id)
	if novo.ok and not novo.data.is_empty():
		_set_dinheiro(float(novo.data[0].dinheiro))
	return r


## Id (em `tipo_minigame`) do primeiro tipo cujo cadastro contém alguma das palavras
## (ignora maiúsculas; olha todos os campos de texto da linha). -1 se não achar.
func tipo_minigame_id(palavras: Array) -> int:
	for t in tipos_minigame:
		if not t is Dictionary:
			continue
		var texto := ""
		for k in t:
			if t[k] is String:
				texto += " " + String(t[k]).to_lower()
		for p in palavras:
			if texto.contains(String(p).to_lower()):
				return _i(t.get("id", -1))
	return -1


## 1234.5 -> "R$ 1.234,50" (mesmo formato usado nas telas de questão e da barra).
func formatar_dinheiro(v: float) -> String:
	var partes := String.num(absf(v), 2).split(".")
	var inteiro := partes[0]
	var out := ""
	while inteiro.length() > 3:
		out = "." + inteiro.substr(inteiro.length() - 3) + out
		inteiro = inteiro.substr(0, inteiro.length() - 3)
	return "R$ " + inteiro + out + "," + partes[1]
## Evolui sozinho quando as questões acertadas do nível e o dinheiro atingem o exigido pelo próximo nível.
func verificar_evolucao() -> void:
	if not game_over_ativo and pode_evoluir():
		await evoluir()


# ------------------------- Game over -------------------------
## Quantas questões do nível atual o aeroporto respondeu errado.
func erros_do_nivel() -> int:
	var n := 0
	for q in questoes_do_nivel(nivel_atual()):
		if respostas.has(q.id) and not respostas[q.id]:
			n += 1
	return n


## Motivo do game over ("" = ainda não é). Regras:
##  - dinheiro <= 0;
##  - erros no nível atual >= questões necessárias para o próximo nível.
func motivo_game_over() -> String:
	if dinheiro() <= 0.0:
		return "Você ficou sem dinheiro, malandro"
	var prox: Dictionary = niveis.get(nivel_atual() + 1, {})
	if not prox.is_empty():
		var limite := _i(prox.questoes_necessarias)
		if limite > 0 and erros_do_nivel() >= limite:
			return "Você errou %d questões neste nível (o limite era %d)" % [erros_do_nivel(), limite]
	return ""


func _avaliar_progresso(acertou: bool) -> void:
	if game_over_ativo or aeroporto_id == "":
		return
	if acertou:
		await verificar_evolucao()
		return
	var motivo := motivo_game_over()
	if motivo != "":
		_iniciar_game_over(motivo)


func _iniciar_game_over(motivo: String) -> void:
	game_over_ativo = true
	reset_ok = false
	game_over.emit(motivo)         # o mapa mostra a tela (depois de fechar a questão aberta)
	await reiniciar_progresso()    # o save é resetado já no game over, qualquer botão que o jogador escolha


## Zera o progresso do save no servidor (nível 1, dinheiro inicial, sem respostas nem aluguéis;
## recordes de minigame são mantidos) e no cache. Retorna {ok, error}.
func reiniciar_progresso() -> Dictionary:
	if _resetando:
		await progresso_reiniciado
		return {"ok": reset_ok, "error": reset_erro}
	_resetando = true
	var r = await GameApi.reiniciar_aeroporto(aeroporto_id)
	reset_ok = r.ok
	reset_erro = "" if r.ok else str(r.error)
	if r.ok:
		respostas.clear()
		concluidas.clear()
		alugueis.clear()
		_vistas = {}
		_ultima_sorteada = -1
		var novo = await GameApi.get_aeroporto(aeroporto_id)
		if novo.ok and novo.data is Array and not novo.data.is_empty():
			aeroporto.merge(novo.data[0], true)
		else:
			aeroporto["nivel_aeroporto_id"] = 1
			aeroporto["fluxo_passageiros"] = 1
		aeroporto["nivel_aeroporto_id"] = _i(aeroporto.get("nivel_aeroporto_id", 1))
		dinheiro_mudou.emit(dinheiro())
		nivel_mudou.emit(nivel_atual())
	_resetando = false
	progresso_reiniciado.emit(reset_ok)
	return {"ok": reset_ok, "error": reset_erro}


func reset_em_andamento() -> bool:
	return _resetando


## O jogador escolheu reiniciar ou voltar ao menu: libera o estado de game over.
func encerrar_game_over() -> void:
	game_over_ativo = false


func _set_dinheiro(v: float) -> void:
	aeroporto["dinheiro"] = v
	dinheiro_mudou.emit(v)
