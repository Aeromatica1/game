extends RefCounted
## Ponto ÚNICO de ligação entre os NPCs/espaços e as questões do jogo.
## Agora usa o cache do GameState (carregado uma vez do Supabase): o sorteio é local,
## e a validação da resposta acontece no servidor (ver tela_questao.gd).
##
## Formato devolvido:
## {
##     "id": 12,
##     "nivel": 1,
##     "enunciado": "Quanto é 7 x 8?",
##     "recompensa": 50.0,
##     "alternativas": [ {"id": 41, "enunciado": "54"}, ... ]   # 4, já embaralhadas
## }
## O servidor não expõe o gabarito: não existe campo "correta" aqui.
##
## Casos especiais:
##  - {}                         -> nenhum save carregado (cena aberta direto): a tela mostra o placeholder.
##  - {"sem_questoes": true, ..} -> o jogador já acertou todas as questões do nível atual.


## `_contexto` identifica quem perguntou (ex.: "checkin", "aluguel_cafeteria"). O sorteio
## hoje é só por nível, mas o parâmetro fica para filtrar por tema no futuro.
static func proxima_questao(_contexto: String = "") -> Dictionary:
	if GameState.aeroporto_id == "":
		return {}
	var q := GameState.sortear_questao()
	if q.is_empty():
		return {
			"sem_questoes": true,
			"enunciado": "Você já acertou todas as questões do nível %d.\nEvolua o aeroporto para liberar novas questões." % GameState.nivel_atual(),
		}
	return q
