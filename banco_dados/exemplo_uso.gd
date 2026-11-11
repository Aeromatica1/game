extends Node
## Exemplo de fluxo completo. Anexe a qualquer Node para testar.

func _ready() -> void:
	# 1) Retoma sessão salva ou faz login
	if not await Supabase.restore_session():
		var r := await Supabase.sign_in("jogador@email.com", "senha-forte-123")
		if not r.ok:
			push_warning("Login falhou: " + r.error)
			return

	# 2) Saves (cria o slot 1 se não existir)
	var saves := await GameApi.listar_saves()
	var aeroporto_id := ""
	if saves.ok and saves.data.is_empty():
		var c := await GameApi.criar_save(1)
		aeroporto_id = c.data if c.ok else ""
	elif saves.ok:
		aeroporto_id = saves.data[0].aeroporto.id

	# 3) Questões do nível 1 (alternativas embaralhadas no cliente)
	var qs := await GameApi.get_questoes(1)
	if qs.ok and not qs.data.is_empty():
		var q: Dictionary = qs.data[0]
		var alts: Array = q.alternativa
		alts.shuffle()
		print(q.enunciado, " -> ", alts)

		# 4) Responder: o servidor diz se acertou
		var resp := await GameApi.responder_questao(aeroporto_id, q.id, alts[0].id)
		if resp.ok:
			print("Acertou? ", resp.data)
		else:
			print("Erro: ", resp.error)   # ex.: "alternativa não pertence à questão"
