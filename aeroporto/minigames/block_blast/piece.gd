class_name Piece
extends Node2D
## Não precisa criar cena: o main.gd cria as peças por código.

signal movendo(piece)
signal soltou(piece)

const LEVANTAR := Vector2(0, -30)   # a peça fica um pouco acima do dedo/mouse

var cells: Array[Vector2i] = []
var textura: Texture2D
var uso := Rect2i()                 # área da imagem que realmente tem desenho (sem a margem transparente)
var cell_size := 16
var bbox := Vector2i.ONE            # largura/altura da peça em células
var home_position := Vector2.ZERO
var home_scale := 0.5               # escala da peça na bandeja
var drag_escala := 1.0              # escala da peça enquanto você arrasta (= escala do grid)
var arrastando := false
var sprite: Sprite2D


func setup(tex: Texture2D, shape: Array, csize: int) -> void:
	cells.assign(shape)
	cell_size = csize
	textura = tex

	var max_x := 0
	var max_y := 0
	for c in cells:
		max_x = maxi(max_x, c.x)
		max_y = maxi(max_y, c.y)
	bbox = Vector2i(max_x + 1, max_y + 1)

	# descobre onde está o desenho dentro da imagem (ignora a parte transparente)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	uso = img.get_used_rect()

	# mostra só a parte com desenho, no tamanho original (sem esticar)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(uso)
	add_child(sprite)

	scale = Vector2.ONE * home_scale


# Pedaço da SUA imagem que corresponde a uma célula da peça.
# É isso que o grid desenha depois que a peça encaixa.
func textura_da_celula(c: Vector2i) -> AtlasTexture:
	var largura := cell_size
	var altura := cell_size
	# a última coluna/linha leva os pixels que sobram da arte (ex.: borda de 1 px)
	if c.x == bbox.x - 1:
		largura = uso.size.x - (bbox.x - 1) * cell_size
	if c.y == bbox.y - 1:
		altura = uso.size.y - (bbox.y - 1) * cell_size

	var at := AtlasTexture.new()
	at.atlas = textura
	at.region = Rect2(
		uso.position.x + c.x * cell_size,
		uso.position.y + c.y * cell_size,
		largura, altura)
	return at


func texturas_das_celulas() -> Array:
	var lista := []
	for c in cells:
		lista.append(textura_da_celula(c))
	return lista


func _tamanho_atual() -> Vector2:
	return Vector2(bbox * cell_size) * scale


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not arrastando:
			if Rect2(global_position, _tamanho_atual()).has_point(get_global_mouse_position()):
				arrastando = true
				z_index = 10
				scale = Vector2.ONE * drag_escala
				_seguir_mouse()
				get_viewport().set_input_as_handled()
		elif not event.pressed and arrastando:
			arrastando = false
			z_index = 0
			soltou.emit(self)
	elif event is InputEventMouseMotion and arrastando:
		_seguir_mouse()


func _seguir_mouse() -> void:
	global_position = get_global_mouse_position() - Vector2(bbox * cell_size) * drag_escala / 2.0 + LEVANTAR * drag_escala
	movendo.emit(self)


func voltar() -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "global_position", home_position, 0.15)
	t.tween_property(self, "scale", Vector2.ONE * home_scale, 0.15)
