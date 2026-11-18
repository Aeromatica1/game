extends Control
## Cena do mapa (lógica). Anexado ao nó raiz de mapa.tscn.
##
## - Monta o resumo do aeroporto (vindo do GameState) e entrega à BarraAeroporto,
##   mantendo-o atualizado quando dinheiro/nível mudam.
## - Permite voltar às telas anteriores via autoload Navegacao (que guarda o
##   histórico do GerenciadorTelas): sinal `voltar_solicitado` da barra (botão Voltar).
## - Esc / ícone de menu abrem e fecham as Opções; F1 abre e fecha a Ajuda (menus_mapa.gd).

const GameOverCena := preload("res://aeroporto/game_over/game_over.tscn")
const MenusMapa := preload("res://aeroporto/mapa/menus_mapa.gd")

@onready var barra_aeroporto: Node = $BarraAeroporto

func _ready() -> void:
	if GameState.aeroporto_id == "":
		push_warning("[Mapa] Nenhum save carregado (cena aberta direto?). A barra ficará sem dados.")

	GameState.carregado.connect(atualizar_barra)
	GameState.carregado.connect(_aplicar_fluxo)
	GameState.nivel_mudou.connect(_aplicar_fluxo.unbind(1))
	GameState.dinheiro_mudou.connect(atualizar_barra.unbind(1))
	GameState.nivel_mudou.connect(atualizar_barra.unbind(1))
	GameState.evoluiu.connect(_ao_evoluir)
	GameState.game_over.connect(_ao_game_over)
	GameState.aluguel_feito.connect(atualizar_barra.unbind(1))
	GameState.progresso_reiniciado.connect(atualizar_barra.unbind(1))

	if barra_aeroporto.has_signal("voltar_solicitado"):
		barra_aeroporto.connect("voltar_solicitado", voltar)

	var menus := MenusMapa.new()
	add_child(menus)
	if barra_aeroporto.has_signal("menu_solicitado"):
		barra_aeroporto.connect("menu_solicitado", menus.alternar_menu)
	if barra_aeroporto.has_method("modo_menu"):
		menus.menu_aberto_mudou.connect(func(aberto: bool): barra_aeroporto.call("modo_menu", aberto))

	atualizar_barra()
	_aplicar_fluxo()
	GameState.verificar_evolucao()      # requisitos já cumpridos (ex.: evolução que falhou antes)


func _ao_evoluir(novo_nivel: int) -> void:
	var info: Dictionary = GameState.niveis.get(novo_nivel, {})
	var nome := str(info.get("descricao", ""))
	_toast("Aeroporto evoluiu para o nível %d%s!" % [novo_nivel, (" - " + nome) if nome != "" else ""])


## Mostra o GAME OVER por cima do mapa (espera o jogador fechar a questão que estiver aberta).
func _ao_game_over(motivo: String) -> void:
	var tela := get_tree().get_first_node_in_group("tela_questao")
	if tela != null and tela.visible:
		await tela.fechada
	if get_tree().get_first_node_in_group("game_over") != null:
		return
	var go := GameOverCena.instantiate()
	add_child(go)
	go.abrir(motivo)


## Aviso rápido no topo da tela (funciona com o jogo pausado).
func _toast(texto: String) -> void:
	var camada := CanvasLayer.new()
	camada.layer = 120
	camada.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(camada)
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.6, 1, 0.65))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camada.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.offset_top = 90
	var tw := camada.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(camada.queue_free)


## Volta para a tela anterior do histórico do GerenciadorTelas.
func voltar() -> void:
	Navegacao.voltar_do_mapa()


## Resumo do aeroporto carregado, pronto para exibir.
func dados_aeroporto() -> Dictionary:
	var nivel := GameState.nivel_atual()
	var prog := GameState.progresso_nivel()           # Vector2i(acertos, total) do nível atual
	var info_nivel: Dictionary = GameState.niveis.get(nivel, {})
	var prox: Dictionary = GameState.niveis.get(nivel + 1, {})
	return {
		"nivel": nivel,
		"nivel_nome": str(info_nivel.get("descricao", "")),
		"dinheiro": GameState.dinheiro(),
		"fluxo_passageiros": float(GameState.aeroporto.get("fluxo_passageiros", 0.0)),
		"questoes_acertadas": prog.x,
		"questoes_do_nivel": prog.y,
		"questoes_acertadas_total": GameState.concluidas.size(),
		"erradas": GameState.erros_do_nivel(),
		"alugueis": GameState.alugueis.size(),
		"alugueis_total": _total_espacos(),
		"minigames": GameState.minigames.duplicate(),   # tipo_minigame_id -> high_score
		"pode_evoluir": GameState.pode_evoluir(),
		# Requisitos do próximo nível ({} se já está no último).
		"proximo_nivel": {} if prox.is_empty() else {
			"dinheiro_necessario": float(prox.get("dinheiro_necessario", 0.0)),
			"questoes_necessarias": int(prox.get("questoes_necessarias", 0)),
			"recompensa": float(prox.get("recompensa", 0.0)),
		},
	}


## Total de espaços alugáveis do mapa (nós do grupo "espacos_aluguel"; 27 se ainda não existirem).
func _total_espacos() -> int:
	var n := get_tree().get_nodes_in_group("espacos_aluguel").size()
	return n if n > 0 else 27


## fluxo_passageiros (1 a 10) é a densidade dos NPCs passageiros do mapa.
func _aplicar_fluxo() -> void:
	if GameState.aeroporto_id != "":
		get_tree().call_group("passageiros", "definir_densidade", GameState.fluxo())


func atualizar_barra() -> void:
	if barra_aeroporto.has_method("atualizar"):
		barra_aeroporto.call("atualizar", dados_aeroporto())
