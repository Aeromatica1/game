extends Control
## Cena de teste: anexe a um Control vazio e rode.
## Pré-requisito: autoloads Supabase, GameApi e GameState registrados.

func _ready() -> void:
	# 1) Sessão
	if not await Supabase.restore_session():
		var r := await Supabase.sign_in("jogador@email.com", "senha-forte-123")
		if not r.ok:
			push_warning("Login falhou: " + r.error)
			return

	# 2) Save: usa o primeiro ou cria o slot 1
	var saves := await GameApi.listar_saves()
	if not saves.ok:
		push_warning(saves.error)
		return
	var aeroporto_id := ""
	if saves.data.is_empty():
		var c := await GameApi.criar_save(1)
		if not c.ok:
			push_warning(c.error)
			return
		aeroporto_id = c.data
	else:
		aeroporto_id = saves.data[0].aeroporto.id

	# 3) UMA requisição carrega o jogo todo para a memória
	var carga := await GameState.carregar(aeroporto_id)
	if not carga.ok:
		push_warning("Falha ao carregar: " + carga.error)
		return

	# 4) Tela de questões (sorteio local; só a validação vai ao servidor)
	var quiz := preload("res://questoes/tela_questao.gd").new()
	quiz.fechada.connect(quiz.queue_free)
	add_child(quiz)
