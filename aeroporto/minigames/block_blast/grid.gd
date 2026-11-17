class_name Grid
extends Node2D
## Anexe este script no nó raiz da cena do Grid (Node2D)
## que tem como filho o Sprite2D com a imagem Grid.png.

const TAM := 8

# Valores medidos no seu Grid.png (200x200):
# a área jogável começa em (36, 37) e cada célula tem 16 px.
@export var cell_size := 16
@export var origem := Vector2(36, 37)
@export var mostrar_debug := false     # ligue para ver as células em rosa por cima da sua arte

var sprite: Sprite2D
var celulas: Array = []                # celulas[y][x] = AtlasTexture (pedaço da arte da peça) ou null
var preview_cells: Array[Vector2i] = []
var preview_ok := true


func _ready() -> void:
	# o sprite do grid fica atrás do que desenhamos aqui, no canto (0, 0) do nó
	for c in get_children():
		if c is Sprite2D:
			c.show_behind_parent = true
			c.centered = false
			c.position = Vector2.ZERO
			sprite = c

	for y in TAM:
		var linha := []
		for x in TAM:
			linha.append(null)
		celulas.append(linha)
	queue_redraw()


# tamanho da imagem do grid em pixels (sem escala)
func tamanho() -> Vector2:
	if sprite != null and sprite.texture != null:
		return sprite.texture.get_size()
	return Vector2(200, 200)


# ---------- conversões ----------
func pos_para_celula(global_pos: Vector2) -> Vector2i:
	var l := to_local(global_pos) - origem
	return Vector2i(floori(l.x / cell_size), floori(l.y / cell_size))


# ---------- regras ----------
func pode_colocar(shape: Array[Vector2i], cel: Vector2i) -> bool:
	for c in shape:
		var p: Vector2i = c + cel
		if p.x < 0 or p.y < 0 or p.x >= TAM or p.y >= TAM:
			return false
		if celulas[p.y][p.x] != null:
			return false
	return true


# texturas[i] é o pedaço da arte da peça que corresponde a shape[i]
func colocar(shape: Array[Vector2i], cel: Vector2i, texturas: Array) -> void:
	for i in shape.size():
		var p: Vector2i = shape[i] + cel
		celulas[p.y][p.x] = texturas[i]
	queue_redraw()


func limpar_linhas() -> int:
	var linhas: Array[int] = []
	var colunas: Array[int] = []

	for y in TAM:
		var cheia := true
		for x in TAM:
			if celulas[y][x] == null:
				cheia = false
				break
		if cheia:
			linhas.append(y)

	for x in TAM:
		var cheia := true
		for y in TAM:
			if celulas[y][x] == null:
				cheia = false
				break
		if cheia:
			colunas.append(x)

	for y in linhas:
		for x in TAM:
			celulas[y][x] = null
	for x in colunas:
		for y in TAM:
			celulas[y][x] = null

	queue_redraw()
	return linhas.size() + colunas.size()


func cabe_em_algum_lugar(shape: Array[Vector2i]) -> bool:
	for y in TAM:
		for x in TAM:
			if pode_colocar(shape, Vector2i(x, y)):
				return true
	return false


# ---------- preview (sombra enquanto arrasta) ----------
func set_preview(shape: Array[Vector2i], cel: Vector2i) -> void:
	preview_ok = pode_colocar(shape, cel)
	preview_cells.clear()
	for c in shape:
		preview_cells.append(c + cel)
	queue_redraw()


func limpar_preview() -> void:
	preview_cells.clear()
	queue_redraw()


# ---------- desenho ----------
func _draw() -> void:
	var tam_cel := Vector2.ONE * cell_size

	# peças já encaixadas, com a SUA arte
	for y in TAM:
		for x in TAM:
			var tex: Texture2D = celulas[y][x]
			if tex != null:
				draw_texture(tex, origem + Vector2(x, y) * cell_size)

	# sombra de onde a peça vai cair
	var cor_prev := Color(0.2, 1, 0.3, 0.35) if preview_ok else Color(1, 0.2, 0.2, 0.35)
	for p in preview_cells:
		if p.x >= 0 and p.y >= 0 and p.x < TAM and p.y < TAM:
			draw_rect(Rect2(origem + Vector2(p) * cell_size, tam_cel), cor_prev)

	if mostrar_debug:
		for y in TAM:
			for x in TAM:
				draw_rect(Rect2(origem + Vector2(x, y) * cell_size, tam_cel), Color(1, 0, 1, 0.5), false)
