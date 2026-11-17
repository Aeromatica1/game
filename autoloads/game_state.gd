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
## Por isso nunca use `.clear()` neles fora de `_atualizar_save`; para "esquecer" o save use `limpar()`.

signal conta_carregada               # terminou (com ou sem sucesso) um carregar_conta()
signal carregado                     # save atual carregado (questões prontas)
signal dinheiro_mudou(valor: float)
signal nivel_mudou(nivel: int)

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

var _ultima_sorteada := -1
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
		func(): return await GameApi.listar_saves(),
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
	# Recarga forçada com um save aberto: reaponta para os dados novos (ou esquece se sumiu).
	if aeroporto_id != "":
		if _dados.has(aeroporto_id):
			_apontar(aeroporto_id)
		else:
			limpar()
	return {"ok": true, "avisos": avisos}


## Rebusca só a lista de saves (ex.: depois de criar um). Saves já em cache não são rebaixados.
func recarregar_saves() -> Dictionary:
	var r = await GameApi.listar_saves()
	if not r.ok:
		return _falha(r.error)
	var avisos := await _aplicar_saves(_como_lista(r.data), true)
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


# Monta `saves` e `_dados` a partir das linhas de save_slot (com aeroporto embutido) e baixa
# respostas/aluguéis/minigames desses aeroportos em paralelo. Retorna avisos não fatais.
func _aplicar_saves(linhas: Array, so_novos: bool) -> Array:
	var avisos := []
	var novos_saves := []
	var aeroportos := {}              # aeroporto_id -> linha de aeroporto
	var precisam: Array = []          # ids cujos detalhes ainda precisam ser baixados
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
		if not (so_novos and _dados.has(aid)):
			precisam.append(aid)
	saves = novos_saves
	for aid in _dados.keys():
		if not aeroportos.has(aid):
			_dados.erase(aid)

	var resp_por: Dictionary = {}
	var alug_por: Dictionary = {}
	var mini_por: Dictionary = {}
	if not precisam.is_empty():
		var res := await _em_paralelo([
			func(): return await GameApi.get_respostas_de(precisam),
			func(): return await GameApi.get_alugueis_de(precisam),
			func(): return await GameApi.get_minigames_de(precisam),
		])
		# Detalhes são secundários: se falharem, os saves ainda aparecem (com esse campo zerado)
		# e entrar no save refresca tudo via carregar_jogo.
		for item in res:
			if not item.ok:
				avisos.append("Detalhes do save indisponíveis: " + item.error)
		if res[0].ok:
			for l in _como_lista(res[0].data):
				var aid := str(l.aeroporto_id)
				if not resp_por.has(aid):
					resp_por[aid] = {}
				var qid := _i(l.questao_id)
				resp_por[aid][qid] = bool(resp_por[aid].get(qid, false)) or bool(l.get("acertou", false))
		if res[1].ok:
			for l in _como_lista(res[1].data):
				var aid := str(l.aeroporto_id)
				if not alug_por.has(aid):
					alug_por[aid] = []
				alug_por[aid].append(l)
		if res[2].ok:
			for l in _como_lista(res[2].data):
				var aid := str(l.aeroporto_id)
				if not mini_por.has(aid):
					mini_por[aid] = {}
				mini_por[aid][_i(l.tipo_minigame_id)] = float(l.high_score)

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

## Escolhe o save: baixa as questões (+ alternativas) e refresca o cache desse save.
func carregar(p_aeroporto_id: String) -> Dictionary:
	if not conta_pronta:
		var c := await carregar_conta()
		if not c.ok:
			return c
	var r = await GameApi.carregar_jogo(p_aeroporto_id)
	if not r.ok:
		return r
	var d: Dictionary = r.data
	_atualizar_save(p_aeroporto_id, d)

	questoes.clear()
	for q in d.get("questoes", []):
		q["id"] = _i(q.id)
		q["nivel"] = _i(q.nivel)
		for a in q.alternativas:
			a["id"] = _i(a.id)
		questoes.append(q)
	_ultima_sorteada = -1

	carregado.emit()
	return r


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
## Sorteia uma questão ainda não acertada do nível atual, dando preferência às nunca
## respondidas (só há 1 resposta por questão por aeroporto; as erradas voltam por último).
## Evita repetir a anterior (quando houver outra opção) e embaralha as alternativas.
## Retorna {} quando o nível acabou.
func sortear_questao() -> Dictionary:
	var pool := questoes_do_nivel(nivel_atual()).filter(func(item): return not concluidas.has(item.id))
	var ineditas := pool.filter(func(item): return not respostas.has(item.id))
	if not ineditas.is_empty():
		pool = ineditas
	if pool.is_empty():
		return {}
	if pool.size() > 1:
		pool = pool.filter(func(item): return item.id != _ultima_sorteada)
	var q: Dictionary = pool.pick_random().duplicate(true)
	var alts: Array = q.alternativas
	alts.shuffle()
	q.alternativas = alts
	_ultima_sorteada = q.id
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
	return r


func pode_evoluir() -> bool:
	var prox: Dictionary = niveis.get(nivel_atual() + 1, {})
	if prox.is_empty():
		return false
	return progresso_nivel().x >= _i(prox.questoes_necessarias) \
		and dinheiro() >= float(prox.dinheiro_necessario)


func evoluir() -> Dictionary:
	var r = await GameApi.evoluir_aeroporto(aeroporto_id)
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
	return r


func _set_dinheiro(v: float) -> void:
	aeroporto["dinheiro"] = v
	dinheiro_mudou.emit(v)
