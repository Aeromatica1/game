extends RefCounted
## Ponto ÚNICO de ligação com o banco de dados de questões.
## Por enquanto devolve um Dictionary vazio, e a tela mostra apenas o espaço em branco.
## Quando o banco existir, é só implementar `proxima_questao()` aqui (HTTP, SQLite, JSON...).
##
## Formato esperado de uma questão:
## {
##     "id": 12,                                   # opcional, só para registro
##     "enunciado": "Quanto é 7 x 8?",
##     "alternativas": ["54", "56", "58", "64"],   # exatamente 4
##     "correta": 1                                # índice 0-3 (ou -1 se não houver gabarito)
## }


## `contexto` identifica quem perguntou (ex.: "checkin", "info", "pesagem"), para você
## poder filtrar por tema/dificuldade no banco.
static func proxima_questao(_contexto: String = "") -> Dictionary:
	return {}
