extends CanvasLayer
## Menus por cima do mapa: Opções (Esc ou ícone de menu da barra) e Ajuda (F1).
## Cada atalho abre e fecha. Enquanto um menu está aberto o jogo fica pausado.
##
## Fica acima do mundo e abaixo da barra (layer 3), para o ícone de menu continuar clicável.
## Roda em PROCESS_MODE_ALWAYS para receber teclas com a árvore pausada.

signal menu_aberto_mudou(aberto: bool)

const OpcoesCena := preload("res://telas/opcoes/opcoes.tscn")
const AjudaCena := preload("res://telas/ajuda/ajuda.tscn")
## Telas que já tratam Esc sozinhas / bloqueiam o jogo: enquanto uma delas está aberta, não abrimos menus.
const GRUPOS_MODAIS := ["tela_questao", "tela_escolha_area", "tela_minigame", "game_over"]

var _fundo: ColorRect
var _opcoes: Control
var _ajuda: Control
var _pausou := false


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fundo = ColorRect.new()
	_fundo.color = Color(0.03, 0.09, 0.15, 0.95)
	_fundo.mouse_filter = Control.MOUSE_FILTER_STOP       # não deixa cliques passarem para o mapa
	_fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fundo.visible = false
	add_child(_fundo)

	_opcoes = OpcoesCena.instantiate()
	_ajuda = AjudaCena.instantiate()
	for tela: Control in [_opcoes, _ajuda]:
		tela.visible = false
		add_child(tela)

	var concluido := _opcoes.get_node_or_null("OpcoesArea/VBoxContainer/Concluido") as Button
	if concluido:
		concluido.pressed.connect(fechar)
	var concluir := _ajuda.get_node_or_null("Concluir") as Button
	if concluir:
		concluir.pressed.connect(fechar)

func _exit_tree() -> void:
	# Mudança de cena com um menu aberto (ex.: botão Voltar): não deixa a árvore pausada.
	if _pausou and get_tree() != null:
		get_tree().paused = false
		_pausou = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		alternar_menu()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		alternar_ajuda()


func aberto() -> bool:
	return _opcoes.visible or _ajuda.visible


## Esc / ícone de menu: fecha o que estiver aberto; senão abre as Opções.
func alternar_menu() -> void:
	if aberto():
		fechar()
	else:
		_abrir(_opcoes)


## F1: fecha a Ajuda se estiver aberta; senão abre (trocando as Opções, se for o caso).
func alternar_ajuda() -> void:
	if _ajuda.visible:
		fechar()
	else:
		_abrir(_ajuda)


func fechar() -> void:
	if not aberto():
		return
	_fundo.visible = false
	_opcoes.visible = false
	_ajuda.visible = false
	if _pausou:
		get_tree().paused = false
		_pausou = false
	menu_aberto_mudou.emit(false)


func _abrir(tela: Control) -> void:
	if _modal_aberto() or GameState.game_over_ativo:
		return
	var ja_aberto := aberto()
	_opcoes.visible = tela == _opcoes
	_ajuda.visible = tela == _ajuda
	_fundo.visible = true
	if not ja_aberto:
		_pausou = not get_tree().paused
		get_tree().paused = true
		menu_aberto_mudou.emit(true)


func _modal_aberto() -> bool:
	for grupo in GRUPOS_MODAIS:
		for n in get_tree().get_nodes_in_group(grupo):
			if n != self and bool(n.get("visible")):
				return true
	return false
