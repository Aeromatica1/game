extends Control
## Cena do mapa (lógica). Anexado ao nó raiz de mapa.tscn.
##
## - Monta o resumo do aeroporto (vindo do GameState) e entrega à BarraAeroporto,
##   mantendo-o atualizado quando dinheiro/nível mudam.
## - Permite voltar às telas anteriores via autoload Navegacao (que guarda o
##   histórico do GerenciadorTelas): tecla Esc (ui_cancel) ou o sinal
##   `voltar_solicitado` da barra, se ela tiver um botão de voltar.

@onready var barra_aeroporto: Node = $BarraAeroporto

func _ready() -> void:
	if GameState.aeroporto_id == "":
		push_warning("[Mapa] Nenhum save carregado (cena aberta direto?). A barra ficará sem dados.")

	GameState.carregado.connect(atualizar_barra)
	GameState.carregado.connect(_aplicar_fluxo)
	GameState.nivel_mudou.connect(_aplicar_fluxo.unbind(1))
	GameState.dinheiro_mudou.connect(atualizar_barra.unbind(1))
	GameState.nivel_mudou.connect(atualizar_barra.unbind(1))

	if barra_aeroporto.has_signal("voltar_solicitado"):
		barra_aeroporto.connect("voltar_solicitado", voltar)

	atualizar_barra()
	_aplicar_fluxo()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		voltar()


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
		"alugueis": GameState.alugueis.size(),
		"minigames": GameState.minigames.duplicate(),   # tipo_minigame_id -> high_score
		"pode_evoluir": GameState.pode_evoluir(),
		# Requisitos do próximo nível ({} se já está no último).
		"proximo_nivel": {} if prox.is_empty() else {
			"dinheiro_necessario": float(prox.get("dinheiro_necessario", 0.0)),
			"questoes_necessarias": int(prox.get("questoes_necessarias", 0)),
			"recompensa": float(prox.get("recompensa", 0.0)),
		},
	}


## fluxo_passageiros (1 a 10) é a densidade dos NPCs passageiros do mapa.
func _aplicar_fluxo() -> void:
	if GameState.aeroporto_id != "":
		get_tree().call_group("passageiros", "definir_densidade", GameState.fluxo())


func atualizar_barra() -> void:
	if barra_aeroporto.has_method("atualizar"):
		barra_aeroporto.call("atualizar", dados_aeroporto())
