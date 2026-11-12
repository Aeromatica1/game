extends CanvasLayer
## Abre qualquer minigame por cima do mapa (jogo pausado) e devolve o controle ao fechar.
## Fecha com Esc, com o botão "Fechar", ou quando o minigame emite `voltar_pressed` / `fechar_pedido`.
##
## Uso:  host.abrir(preload("res://minigames/minesweeper/game.tscn"), "Atendente")
## Sinal `fechado` avisa quando o jogador saiu (dá para ligar recompensa/progresso aqui depois).

signal fechado

var _raiz: Control
var _titulo: Label
var _atual: Node
var _aberta := false


func _init() -> void:
	add_to_group("tela_minigame")
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_raiz)
	var fundo := ColorRect.new()
	fundo.color = Color(0.04, 0.05, 0.1, 1.0)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(fundo)

	var barra := HBoxContainer.new()
	barra.set_anchors_preset(Control.PRESET_TOP_WIDE)
	barra.offset_left = 12
	barra.offset_right = -12
	barra.offset_top = 8
	barra.z_index = 10
	_raiz.add_child(barra)
	_titulo = Label.new()
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barra.add_child(_titulo)
	var b := Button.new()
	b.text = "Fechar  (Esc)"
	b.pressed.connect(fechar)
	barra.add_child(b)


func abrir(cena: PackedScene, titulo: String = "") -> void:
	if _aberta:
		return
	_atual = cena.instantiate()
	_atual.process_mode = Node.PROCESS_MODE_ALWAYS # roda mesmo com o mapa pausado
	_atual.set_meta("embutido", true)
	if _atual.has_signal("voltar_pressed"):
		_atual.connect("voltar_pressed", fechar)
	if _atual.has_signal("fechar_pedido"):
		_atual.connect("fechar_pedido", fechar)
	_raiz.add_child(_atual)
	_raiz.move_child(_atual, 1) # acima do fundo, abaixo da barra
	_titulo.text = titulo
	_aberta = true
	visible = true
	get_tree().paused = true


func fechar() -> void:
	if not _aberta:
		return
	_aberta = false
	if is_instance_valid(_atual):
		_atual.queue_free()
	_atual = null
	visible = false
	get_tree().paused = false
	fechado.emit()


func _input(event: InputEvent) -> void:
	if _aberta and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		fechar()
		get_viewport().set_input_as_handled()
