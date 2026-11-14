extends Node
 
## Autoload "GameState": cache em memória do jogo.
##
## Fluxo:  1) carregar() faz UMA requisição e guarda tudo aqui;
##         2) sorteio de questões, telas, contas de nível etc. rodam local, sem rede;
##         3) só ações que mudam dinheiro/progresso (responder, alugar, evoluir...)
##            vão ao servidor, que valida e devolve o novo estado.
## O servidor continua sendo a fonte da verdade: o cache nunca é "enviado de volta".

signal carregado
signal dinheiro_mudou(valor: float)
signal nivel_mudou(nivel: int)

var aeroporto_id := ""
var aeroporto := {}                 # id, nivel_aeroporto_id, dinheiro, fluxo_passageiros
var niveis := {}                    # nivel(int) -> {id, descricao, bonus, dinheiro_necessario, questoes_necessarias}
var questoes: Array[Dictionary] = []  # {id, nivel, enunciado, recompensa, alternativas:[{id, enunciado}]}
var concluidas := {}                # questao_id(int) -> true (acertadas)
var alugueis: Array = []
var minigames := {}                 # tipo_minigame_id(int) -> high_score
var tipos_aluguel: Array = []
var tipos_minigame: Array = []
var _ultima_sorteada := -1


# JSON do Godot devolve todo número como float; normalizamos ids para int
# (se mandar 1.0 de volta, o Postgres rejeita "1.0" como integer).
static func _i(v: Variant) -> int:
	return int(v)


func carregar(p_aeroporto_id: String) -> Dictionary:
	var r := await GameApi.carregar_jogo(p_aeroporto_id)
	if not r.ok:
		return r
	var d: Dictionary = r.data
	aeroporto_id = p_aeroporto_id
	aeroporto = d.get("aeroporto", {})
	aeroporto["nivel_aeroporto_id"] = _i(aeroporto.get("nivel_aeroporto_id", 1))

	niveis.clear()
	for n in d.get("niveis", []):
		niveis[_i(n.id)] = n

	questoes.clear()
	for q in d.get("questoes", []):
		q["id"] = _i(q.id)
		q["nivel"] = _i(q.nivel)
		for a in q.alternativas:
			a["id"] = _i(a.id)
		questoes.append(q)

	concluidas.clear()
	for qid in d.get("questoes_concluidas", []):
		concluidas[_i(qid)] = true

	alugueis = d.get("alugueis", [])
	tipos_aluguel = d.get("tipos_aluguel", [])
	tipos_minigame = d.get("tipos_minigame", [])
	minigames.clear()
	for m in d.get("minigames", []):
		minigames[_i(m.tipo_minigame_id)] = float(m.high_score)

	carregado.emit()
	return r


# ------------------------- Leitura do estado -------------------------
func nivel_atual() -> int:
	return _i(aeroporto.get("nivel_aeroporto_id", 1))

func dinheiro() -> float:
	return float(aeroporto.get("dinheiro", 0.0))

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
## Sorteia uma questão ainda não acertada do nível atual.
## Evita repetir a anterior (quando houver outra opção) e embaralha as alternativas.
## Retorna {} quando o nível acabou.
func sortear_questao() -> Dictionary:
	var pool := questoes_do_nivel(nivel_atual()).filter(func(item): return not concluidas.has(item.id))
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
	var r := await GameApi.responder_questao(aeroporto_id, questao_id, alternativa_id)
	if not r.ok:
		return r
	var d: Dictionary = r.data
	if d.get("acertou", false):
		concluidas[questao_id] = true
	_set_dinheiro(float(d.get("dinheiro", dinheiro())))
	return r


func pode_evoluir() -> bool:
	var prox: Dictionary = niveis.get(nivel_atual() + 1, {})
	if prox.is_empty():
		return false
	return progresso_nivel().x >= _i(prox.questoes_necessarias) \
		and dinheiro() >= float(prox.dinheiro_necessario)


func evoluir() -> Dictionary:
	var r := await GameApi.evoluir_aeroporto(aeroporto_id)
	if r.ok:
		aeroporto["nivel_aeroporto_id"] = _i(r.data)
		# O servidor descontou o custo; recarregamos só o dinheiro para não divergir.
		var novo := await GameApi.get_aeroporto(aeroporto_id)
		if novo.ok and not novo.data.is_empty():
			_set_dinheiro(float(novo.data[0].dinheiro))
		nivel_mudou.emit(nivel_atual())
	return r


func _set_dinheiro(v: float) -> void:
	aeroporto["dinheiro"] = v
	dinheiro_mudou.emit(v)
