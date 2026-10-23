
extends Control

# CONFIGURACAO DO JOGO


const GRID_SIZE: int = 8
const CELL_SIZE: int = 32
const CELL_GAP: int = 2
const STEP: int = CELL_SIZE + CELL_GAP
var placed_pieces: Array = []
var next_piece_id: int = 0

const BOARD_SIZE: int = (
	GRID_SIZE * CELL_SIZE
	+ (GRID_SIZE - 1) * CELL_GAP
)

# Posicao da grade na tela
const BOARD_POS := Vector2(345, 65)

# Posicoes das tres pecas disponiveis
const TRAY_POSITIONS := [
	Vector2(155, 410),
	Vector2(415, 410),
	Vector2(675, 410)
]

# ==========================================
# assets
# Troque os caminhos pelos seus arquivos.
# ==========================================

const PIECE_TEXTURES = {
	"-": "res://assets/pecas/--.png",
	"I": "res://assets/pecas/I.png",
	"O": "res://assets/pecas/O.png",
	"T": "res://assets/pecas/T.png",
	"L": "res://assets/pecas/L.png",
	"J": "res://assets/pecas/J.png",
	"S": "res://assets/pecas/S.png",
	"Z": "res://assets/pecas/Z.png"
}

# Cada coordenada representa um quadrado da peca.
# (0, 0) e o quadrado do canto superior esquerdo.

const SHAPES = {
	"I": [
		Vector2i(0,0),
		Vector2i(0,1),
		Vector2i(0,2),
		Vector2i(0,3)
	],
	"-": [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0)
	],
	"O": [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1)
	],
	"T": [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(1, 1)
	],
	"L": [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(0, 2),
		Vector2i(1, 2)
	],
	"J": [
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(1, 2),
		Vector2i(0, 2)
	],
	"S": [
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(0, 1),
		Vector2i(1, 1)
	],
	"Z": [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(2, 1)
	]
}

const PIECE_COLORS = {
	"I": Color("#36C5F0"),
	"O": Color("#F4D03F"),
	"T": Color("#A66CFF"),
	"L": Color("#FF9F43"),
	"J": Color("#4287F5"),
	"S": Color("#55D68B"),
	"Z": Color("#F05D68")
}

# ==========================================
# VARIAVEIS
# ==========================================

# null = celula vazia.
# String = identificador da peca que ocupou a celula.
var grid: Array = []

var textures: Dictionary = {}
var available_pieces: Array = []

var selected_slot: int = -1
var score: int = 0
var game_over: bool = false


func _ready() -> void:
	load_textures()
	reset_grid()
	generate_pieces()
	queue_redraw()


func load_textures() -> void:
	for piece_name in PIECE_TEXTURES:
		var path: String = PIECE_TEXTURES[piece_name]

		if ResourceLoader.exists(path):
			textures[piece_name] = load(path)
		else:
			push_warning(
				"Asset nao encontrado: " + path
			)


func reset_grid() -> void:
	grid.clear()

	for y in range(GRID_SIZE):
		var row: Array = []

		for x in range(GRID_SIZE):
			row.append(null)

		grid.append(row)




func generate_pieces() -> void:
	available_pieces.clear()

	var names: Array = SHAPES.keys()

	for i in range(3):
		var random_index: int = randi_range(
			0, names.size() - 1
		)

		available_pieces.append(names[random_index])

	selected_slot = -1
	game_over = not has_any_valid_move()

	queue_redraw()




func _draw() -> void:
	draw_interface()
	draw_grid()
	draw_placed_blocks()
	draw_piece_tray()

	if selected_slot >= 0 and not game_over:
		draw_placement_preview()


func draw_interface() -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(345, 35),
		"BLOCK BLAST",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		24,
		Color.WHITE
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(345, 55),
		"Pontuacao: " + str(score),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		15,
		Color("#C5CEE0")
	)

	if game_over:
		draw_rect(
			Rect2(BOARD_POS, Vector2(BOARD_SIZE, BOARD_SIZE)),
			Color(0, 0, 0, 0.72)
		)

		draw_string(
			ThemeDB.fallback_font,
			BOARD_POS + Vector2(25, BOARD_SIZE / 2),
			"FIM DE JOGO!",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			25,
			Color.WHITE
		)


func draw_grid() -> void:
	# Fundo da grade
	draw_rect(
		Rect2(
			BOARD_POS - Vector2(5, 5),
			Vector2(BOARD_SIZE + 10, BOARD_SIZE + 10)
		),
		Color("#20283A")
	)

	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos: Vector2 = cell_position(x, y)

			draw_rect(
				Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE)),
				Color("#344057")
			)



func draw_placed_blocks() -> void:
	# Desenha cada celula separadamente. Assim, quando uma linha/coluna
	# for eliminada, os pedacos correspondentes da mala tambem desaparecem.
	for piece in placed_pieces:
		var piece_name: String = piece["name"]
		var origin: Vector2i = piece["origin"]
		var piece_id: int = piece["id"]

		if not textures.has(piece_name):
			continue

		var texture: Texture2D = textures[piece_name]
		var cells: Array = SHAPES[piece_name]
		var max_x: int = 0
		var max_y: int = 0

		for cell in cells:
			max_x = max(max_x, cell.x)
			max_y = max(max_y, cell.y)

		# Divide a textura em partes correspondentes as celulas do formato.
		# As artes devem ter a mesma proporcao do retangulo da peca.
		var source_cell_width: float = float(texture.get_width()) / float(max_x + 1)
		var source_cell_height: float = float(texture.get_height()) / float(max_y + 1)

		for cell in cells:
			var target: Vector2i = origin + cell

			# Se a celula foi apagada, nao desenha mais aquele pedaco.
			if not is_inside_grid(target):
				continue
			if grid[target.y][target.x] != piece_id:
				continue

			var source_rect := Rect2(
				cell.x * source_cell_width,
				cell.y * source_cell_height,
				source_cell_width,
				source_cell_height
			)
			var destination_rect := Rect2(
				cell_position(target.x, target.y),
				Vector2(CELL_SIZE, CELL_SIZE)
			)

			draw_texture_rect_region(texture, destination_rect, source_rect)


func draw_piece_tray() -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(155, 390),
		"SUAS pecas",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color("#C5CEE0")
	)

	for i in range(available_pieces.size()):
		var piece_name = available_pieces[i]

		if piece_name == null:
			continue

		var slot_pos: Vector2 = TRAY_POSITIONS[i]

		if selected_slot == i:
			draw_rect(
				Rect2(
					slot_pos - Vector2(8, 8),
					Vector2(115, 100)
				),
				Color("#3A4965")
			)

		draw_piece_preview(
			piece_name,
			slot_pos,
			24.0
		)


func draw_piece_preview(
	piece_name: String,
	origin: Vector2,
	preview_cell: float
) -> void:
	var shape: Array = SHAPES[piece_name]
	var max_x: int = 0
	var max_y: int = 0

	for cell in shape:
		max_x = max(max_x, cell.x)
		max_y = max(max_y, cell.y)

	var piece_width: float = (max_x + 1) * preview_cell
	var piece_height: float = (max_y + 1) * preview_cell

	if textures.has(piece_name):
		var texture: Texture2D = textures[piece_name]

		# Escala uniforme: preserva a proporcao original da pixel art.
		var scale_x: float = piece_width / float(texture.get_width())
		var scale_y: float = piece_height / float(texture.get_height())
		var scale_factor: float = min(scale_x, scale_y)
		var draw_size := Vector2(
			texture.get_width() * scale_factor,
			texture.get_height() * scale_factor
		)
		var centered_origin := origin + Vector2(
			(piece_width - draw_size.x) / 2.0,
			(piece_height - draw_size.y) / 2.0
		)

		draw_texture_rect(
			texture,
			Rect2(centered_origin, draw_size),
			false,
			Color.WHITE,
			false
		)
	else:
		# Alternativa caso o arquivo de imagem nao exista.
		for cell in shape:
			draw_rect(
				Rect2(
					origin + Vector2(cell) * preview_cell,
					Vector2(preview_cell - 2, preview_cell - 2)
				),
				PIECE_COLORS[piece_name]
			)


func draw_placement_preview() -> void:
	var piece_name = available_pieces[selected_slot]

	if piece_name == null:
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	var origin_cell: Vector2i = mouse_to_cell(mouse_pos)

	var valid: bool = can_place_piece(
		piece_name,
		origin_cell
	)

	var preview_color: Color

	if valid:
		preview_color = Color(0.3, 1.0, 0.5, 0.55)
	else:
		preview_color = Color(1.0, 0.2, 0.2, 0.45)

	for cell in SHAPES[piece_name]:
		var target: Vector2i = origin_cell + cell

		if is_inside_grid(target):
			draw_rect(
				Rect2(
					cell_position(target.x, target.y),
					Vector2(CELL_SIZE, CELL_SIZE)
				),
				preview_color
			)


# ==========================================
# POSICOES E ENCAIXE
# ==========================================

func cell_position(x: int, y: int) -> Vector2:
	return BOARD_POS + Vector2(x * STEP, y * STEP)


func mouse_to_cell(mouse_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = mouse_pos - BOARD_POS

	return Vector2i(
		floori(local_pos.x / STEP),
		floori(local_pos.y / STEP)
	)


func is_inside_grid(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < GRID_SIZE
		and cell.y >= 0
		and cell.y < GRID_SIZE
	)


func can_place_piece(
	piece_name: String,
	origin: Vector2i
) -> bool:
	for cell in SHAPES[piece_name]:
		var target: Vector2i = origin + cell

		if not is_inside_grid(target):
			return false

		if grid[target.y][target.x] != null:
			return false

	return true



func place_piece(
	piece_name: String,
	origin: Vector2i
) -> void:
	if not can_place_piece(piece_name, origin):
		return

	# Cada peca recebe um identificador proprio. Isso evita confundir
	# duas malas do mesmo tipo depois que uma linha for eliminada.
	var piece_id: int = next_piece_id
	next_piece_id += 1

	placed_pieces.append({
		"id": piece_id,
		"name": piece_name,
		"origin": origin
	})

	# Guarda o identificador da peca em cada celula ocupada.
	for cell in SHAPES[piece_name]:
		var target: Vector2i = origin + cell
		grid[target.y][target.x] = piece_id

	score += SHAPES[piece_name].size()

	clear_completed_lines()

	available_pieces[selected_slot] = null
	selected_slot = -1

	var all_used: bool = true

	for piece in available_pieces:
		if piece != null:
			all_used = false
			break

	if all_used:
		generate_pieces()
	else:
		game_over = not has_any_valid_move()

	queue_redraw()



# ELIMINACAO DE LINHAS E COLUNAS

func clear_completed_lines() -> void:
	var rows_to_clear: Array[int] = []
	var cols_to_clear: Array[int] = []

	# Procura linhas completas.
	for y in range(GRID_SIZE):
		var full: bool = true

		for x in range(GRID_SIZE):
			if grid[y][x] == null:
				full = false
				break

		if full:
			rows_to_clear.append(y)

	# Procura colunas completas.
	for x in range(GRID_SIZE):
		var full: bool = true

		for y in range(GRID_SIZE):
			if grid[y][x] == null:
				full = false
				break

		if full:
			cols_to_clear.append(x)

	# Limpa todas as linhas identificadas.
	for y in rows_to_clear:
		for x in range(GRID_SIZE):
			grid[y][x] = null

	# Limpa todas as colunas identificadas.
	for x in cols_to_clear:
		for y in range(GRID_SIZE):
			grid[y][x] = null

	var cleared_count: int = (
		rows_to_clear.size() + cols_to_clear.size()
	)

	score += cleared_count * GRID_SIZE




func has_any_valid_move() -> bool:
	for piece_name in available_pieces:
		if piece_name == null:
			continue

		for y in range(GRID_SIZE):
			for x in range(GRID_SIZE):
				if can_place_piece(
					piece_name,
					Vector2i(x, y)
				):
					return true

	return false


# CONTROLES DO MOUSE

func _input(event: InputEvent) -> void:
	if game_over:
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		):
			reset_game()

		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				select_piece_at_mouse()
			elif selected_slot >= 0:
				var piece_name = available_pieces[selected_slot]

				if piece_name != null:
					var origin: Vector2i = mouse_to_cell(
						get_global_mouse_position()
					)

					if can_place_piece(piece_name, origin):
						place_piece(piece_name, origin)

				queue_redraw()

	elif event is InputEventMouseMotion:
		if selected_slot >= 0:
			queue_redraw()


func select_piece_at_mouse() -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()

	for i in range(available_pieces.size()):
		if available_pieces[i] == null:
			continue

		var slot_rect := Rect2(
			TRAY_POSITIONS[i] - Vector2(10, 10),
			Vector2(120, 100)
		)

		if slot_rect.has_point(mouse_pos):
			selected_slot = i
			queue_redraw()
			return


func reset_game() -> void:
	score = 0
	game_over = false
	selected_slot = -1
	placed_pieces.clear()
	next_piece_id = 0

	reset_grid()
	generate_pieces()
	queue_redraw()
