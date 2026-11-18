extends CanvasLayer
## Tela de GAME OVER (por cima do mapa, com o jogo pausado).
## O progresso do save é resetado pelo GameState assim que o game over acontece; os botões só
## liberam quando o reset termina (se falhar, "Reiniciar" tenta de novo).
##
## Uso:  var tela = preload("res://aeroporto/game_over/game_over.tscn").instantiate()
##       add_child(tela);  tela.abrir("Você ficou sem dinheiro")

@onready var mensagem: Label = $GameOverArea/AreaMensagem/Mensagem
@onready var botao_reiniciar: Button = $GameOverArea/Botoes/BotaoReiniciar
@onready var botao_menu: Button = $GameOverArea/Botoes/BotaoMenu

var _motivo := ""


func _ready() -> void:
	add_to_group("game_over")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mensagem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mensagem.custom_minimum_size.x = 720
	mensagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	botao_reiniciar.pressed.connect(_reiniciar)
	botao_menu.pressed.connect(_menu)
	_botoes(false)


func abrir(motivo: String) -> void:
	_motivo = motivo
	mensagem.text = motivo
	visible = true
	get_tree().paused = true
	_botoes(false)
	if GameState.reset_em_andamento():
		await GameState.progresso_reiniciado
	_pos_reset()


func _pos_reset() -> void:
	if GameState.reset_ok:
		mensagem.text = _motivo
	else:
		mensagem.text = "%s\n\n(Não foi possível resetar o save: %s)" % [_motivo, GameState.reset_erro]
	_botoes(true)


func _botoes(habilitados: bool) -> void:
	botao_reiniciar.disabled = not habilitados
	botao_menu.disabled = not habilitados
	if habilitados:
		botao_reiniciar.grab_focus()


## Garante o reset no servidor (tenta de novo se tinha falhado). true = pode seguir.
func _garantir_reset() -> bool:
	if GameState.reset_ok:
		return true
	_botoes(false)
	var r: Dictionary = await GameState.reiniciar_progresso()
	_pos_reset()
	return r.ok


func _reiniciar() -> void:
	if not await _garantir_reset():
		return
	GameState.encerrar_game_over()
	get_tree().paused = false
	get_tree().reload_current_scene()      # recarrega o mapa já com o save zerado


func _menu() -> void:
	if not await _garantir_reset():
		return
	GameState.encerrar_game_over()
	GameState.limpar()
	get_tree().paused = false
	Navegacao.voltar_ao_menu()
