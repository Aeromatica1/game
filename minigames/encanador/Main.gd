extends Node2D
## Jogo do Encanador com esteiras (Godot 4.x)
## Clique esquerdo = gira 90° horário | Clique direito = gira 90° anti-horário
## Objetivo: ligar o INÍCIO (azul, à esquerda) ao FIM (verde, à direita) antes do tempo acabar.
## Ao conectar, a MALA percorre a rota montada pelo jogador.

# ---------------------------------------------------------------- SPRITES ---
# Coloque os PNGs na raiz do projeto (res://) ou ajuste os caminhos abaixo.
const TEX_I: Texture2D = preload("res://assets/PecasEncanador/Esteira I.png") # 32x32 - reta (vertical)
const TEX_L: Texture2D = preload("res://assets/PecasEncanador/Esteira L.png") # 64x64 - curva (liga DIREITA + BAIXO)
# Segunda curva (espelhada, liga ESQUERDA + BAIXO). O arquivo enviado se chama "Esteira__I.png",
# mas o desenho é uma curva. Se renomear o arquivo, mude o caminho aqui.
const TEX_L2: Texture2D = preload("res://assets/PecasEncanador/Esteira__I.png") # 64x64

# Arte opcional do grid em pixel art (cada uma 64x64). Se o arquivo não existir,
# o jogo usa quadrados de cor no lugar.
const GRID_CELL_PATH := "res://Grid_Celula.png"   # célula normal
const GRID_EMPTY_PATH := "res://Grid_Vazio.png"   # célula sem peça

# Sprite da mala: quando você criar o PNG, salve com este nome/caminho.
# Enquanto o arquivo não existir, um retângulo marrom é usado no lugar.
const MALA_PATH := "res://Mala.png"
const MALA_MAX_SIZE := 40.0      # a mala é reduzida automaticamente se passar disso (px)
const DELIVERY_SPEED := 280.0    # velocidade da mala em pixels por segundo

# ---------------------------------------------------------------- GRADE -----
const MIN_SIZE := 4       # tamanho da grade no nível 1 (4x4)
const MAX_SIZE := 9       # tamanho máximo (9x9) - cresce 1 por nível
const HUD_W := 512        # largura fixa do HUD (barra de tempo, textos)
const BOARD_TOP := 100    # onde começa a área do tabuleiro (abaixo do HUD)
const BOARD_BOTTOM_MARGIN := 10
const CELL := 64          # tamanho de cada célula em pixels
const BELT_W := 32        # largura da esteira (= tamanho do sprite reto)
const MARGIN := 16        # (CELL - BELT_W) / 2  -> esteira centralizada na célula
const L_CROP := 48        # parte do sprite L usada (CELL - MARGIN)
const PORT_W := 40        # largura dos marcadores de início/fim

# Dificuldade: chance de uma célula FORA do caminho ficar vazia (sem peça).
# Começa alta (jogo mais fácil) e diminui a cada nível.
const EMPTY_START := 0.55
const EMPTY_MIN := 0.25
const EMPTY_STEP := 0.04

# Direções como bits
const UP := 1
const RIGHT := 2
const DOWN := 4
const LEFT := 8
const DIRS := [UP, RIGHT, DOWN, LEFT]
const VEC := {
	UP: Vector2i(0, -1),
	RIGHT: Vector2i(1, 0),
	DOWN: Vector2i(0, 1),
	LEFT: Vector2i(-1, 0),
}

enum Kind { I, L, L2 }
enum State { PLAYING, DELIVERING, WON, LOST }

# Cores
const COLOR_BG := Color("#2b2f3a")
const COLOR_BOARD := Color("#c9ccd2")
const COLOR_CELL_A := Color("#c9ccd2")
const COLOR_CELL_B := Color("#bfc3ca")
const COLOR_EMPTY := Color("#9da1ab")
const COLOR_EMPTY_INNER := Color("#8a8e99")
const COLOR_POWERED := Color(1.5, 2.5, 4.0)  # tinge de azul as esteiras conectadas
const COLOR_IN := Color("#2f7dff")
const COLOR_OUT_OFF := Color("#2e8b57")
const COLOR_OUT_ON := Color("#5dff9a")


class Tile:
	var node: Node2D
	var visual: Node2D
	var kind: int = 0
	var steps: int = 0        # quartos de volta acumulados (pode ser negativo)
	var tween: Tween


var level := 1
var score := 0
var moves := 0
var time_left := 0.0
var time_total := 0.0
var state: int = State.PLAYING
var lock_until := 0

var cols := MIN_SIZE
var rows := MIN_SIZE
var board_bg: ColorRect
var start_row := 0
var end_row := 0
var grid: Array = []

var board: Node2D
var level_root: Node2D
var out_port: ColorRect

var moves_label: Label
var score_label: Label
var level_label: Label
var time_bar: ProgressBar
var dim: ColorRect
var msg_label: Label


# ---------------------------------------------------------------- SETUP -----
func _ready() -> void:
	RenderingServer.set_default_clear_color(COLOR_BG)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art nítida

	var vp := get_viewport_rect().size
	board = Node2D.new()
	add_child(board)

	board_bg = ColorRect.new()
	board_bg.color = COLOR_BOARD
	board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(board_bg)

	_build_hud(vp)
	_new_level()


func _build_hud(vp: Vector2) -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var bx := (vp.x - HUD_W) / 2.0

	moves_label = _make_label(hud, Vector2(bx, 12), 24)
	score_label = _make_label(hud, Vector2(bx + 220, 12), 24)
	level_label = _make_label(hud, Vector2(bx + 400, 12), 24)

	var time_text := _make_label(hud, Vector2(bx, 56), 22)
	time_text.text = "TEMPO"

	time_bar = ProgressBar.new()
	time_bar.position = Vector2(bx + 90, 58)
	time_bar.size = Vector2(HUD_W - 90, 26)
	time_bar.show_percentage = false
	time_bar.step = 0.01
	time_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#3fbf3f")
	var back := StyleBoxFlat.new()
	back.bg_color = Color("#c0392b")
	time_bar.add_theme_stylebox_override("fill", fill)
	time_bar.add_theme_stylebox_override("background", back)
	hud.add_child(time_bar)

	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = vp
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	hud.add_child(dim)

	msg_label = _make_label(hud, Vector2(0, vp.y / 2.0 - 90), 36)
	msg_label.size = Vector2(vp.x, 180)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_constant_override("outline_size", 10)
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.visible = false


func _make_label(parent: Node, pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- NÍVEL -----
## Tamanho da grade: 4x4 no nível 1, +1 por nível, até 9x9 (nível 6 em diante).
func _grid_size() -> int:
	return clampi(MIN_SIZE + level - 1, MIN_SIZE, MAX_SIZE)


## Grades maiores têm mais tempo; depois do 9x9 o tempo vai diminuindo.
func _level_time() -> float:
	var n := _grid_size()
	var t := 20.0 + n * 5.0
	var extra_levels := maxi(0, level - (MAX_SIZE - MIN_SIZE + 1))
	return maxf(30.0, t - extra_levels * 3.0)


## Ajusta tamanho, escala e posição do tabuleiro para a grade atual.
func _layout_board() -> void:
	var vp := get_viewport_rect().size
	var px := float(cols * CELL)
	var avail := vp.y - BOARD_TOP - BOARD_BOTTOM_MARGIN
	var s := minf(1.0, avail / px)   # só reduz se não couber (ex.: 9x9)
	board.scale = Vector2(s, s)
	board.position = Vector2(
		(vp.x - px * s) / 2.0,
		BOARD_TOP + (avail - px * s) / 2.0
	)
	board_bg.size = Vector2(px, px)


func _empty_chance() -> float:
	return clampf(EMPTY_START - (level - 1) * EMPTY_STEP, EMPTY_MIN, EMPTY_START)


func _random_curve() -> int:
	return Kind.L if randf() < 0.5 else Kind.L2


func _new_level() -> void:
	state = State.PLAYING
	moves = 0
	time_total = _level_time()
	time_left = time_total
	dim.visible = false
	msg_label.visible = false

	if level_root:
		level_root.queue_free()
	level_root = Node2D.new()
	board.add_child(level_root)

	cols = _grid_size()
	rows = cols
	_layout_board()

	start_row = randi_range(0, rows - 1)
	end_row = randi_range(0, rows - 1)

	# 1) cria um caminho garantido entre o início e o fim
	var path := _make_path()
	var path_masks := {}
	for i in path.size():
		var pc: Vector2i = path[i]
		var d_in: int = LEFT if i == 0 else _dir_to(pc, path[i - 1])
		var d_out: int = RIGHT if i == path.size() - 1 else _dir_to(pc, path[i + 1])
		path_masks[pc] = d_in | d_out

	# 2) decide o tipo de cada célula. As do caminho sempre têm peça;
	#    as outras podem ficar VAZIAS (sem entrada em "kinds").
	var empty_chance := _empty_chance()
	var kinds := {}
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			if path_masks.has(c):
				var m: int = path_masks[c]
				var straight := (m == (UP | DOWN) or m == (LEFT | RIGHT))
				kinds[c] = Kind.I if straight else _random_curve()
			elif randf() >= empty_chance:
				kinds[c] = Kind.I if randf() < 0.45 else _random_curve()

	# 3) fundo do grid (atrás de tudo) e marcadores de início/fim
	_make_cell_backgrounds(kinds)
	_make_markers()

	# 4) cria as peças e embaralha
	grid = []
	for y in rows:
		var row := []
		for x in cols:
			var c := Vector2i(x, y)
			if kinds.has(c):
				var t := _make_tile(kinds[c], x, y)
				t.steps = randi_range(0, 3)
				t.visual.rotation = t.steps * PI / 2.0
				row.append(t)
			else:
				row.append(null)   # célula vazia
		grid.append(row)

	# nunca começa já resolvido
	var first: Vector2i = path[0]
	while _compute_flow()["solved"]:
		var t0: Tile = grid[first.y][first.x]
		t0.steps += 1
		t0.visual.rotation = t0.steps * PI / 2.0

	_refresh_flow()
	_update_hud()


func _load_optional(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Fundo de cada célula: usa os PNGs 64x64 se existirem, senão quadrados de cor.
func _make_cell_backgrounds(kinds: Dictionary) -> void:
	var tex_cell := _load_optional(GRID_CELL_PATH)
	var tex_empty := _load_optional(GRID_EMPTY_PATH)
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			var is_empty := not kinds.has(c)
			var tex := tex_empty if is_empty else tex_cell
			if tex:
				var sp := Sprite2D.new()
				sp.texture = tex
				sp.centered = false
				sp.position = Vector2(c) * CELL
				level_root.add_child(sp)
			else:
				var r := ColorRect.new()
				r.size = Vector2(CELL, CELL)
				r.position = Vector2(c) * CELL
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if is_empty:
					r.color = COLOR_EMPTY
					var inner := ColorRect.new()   # "buraco" afundado
					inner.color = COLOR_EMPTY_INNER
					inner.size = Vector2(CELL - 16, CELL - 16)
					inner.position = Vector2(8, 8)
					inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
					r.add_child(inner)
				else:
					r.color = COLOR_CELL_A if (x + y) % 2 == 0 else COLOR_CELL_B
				level_root.add_child(r)


# ------------------------------------------------- INÍCIO / FIM (marcadores) --
func _make_markers() -> void:
	_make_cell_highlight(Vector2i(0, start_row), Color(COLOR_IN, 0.35))
	_make_cell_highlight(Vector2i(cols - 1, end_row), Color(COLOR_OUT_OFF, 0.35))
	var in_port := _make_port(true)
	in_port.color = COLOR_IN
	out_port = _make_port(false)
	out_port.color = COLOR_OUT_OFF


func _make_cell_highlight(c: Vector2i, color: Color) -> void:
	var r := ColorRect.new()
	r.color = color
	r.size = Vector2(CELL, CELL)
	r.position = Vector2(c) * CELL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_root.add_child(r)


func _make_port(is_start: bool) -> ColorRect:
	var row := start_row if is_start else end_row
	var cy := row * CELL + CELL / 2.0
	var x := -PORT_W if is_start else cols * CELL

	var r := ColorRect.new()
	r.size = Vector2(PORT_W, BELT_W + 12)
	r.position = Vector2(x, cy - r.size.y / 2.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_root.add_child(r)

	# seta branca animada apontando para a direita (sentido do fluxo)
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, -10), Vector2(16, 0), Vector2(0, 10)])
	arrow.color = Color.WHITE
	var base_x := PORT_W / 2.0 - 10.0
	arrow.position = Vector2(base_x, r.size.y / 2.0)
	r.add_child(arrow)
	var tw := arrow.create_tween().set_loops()
	tw.tween_property(arrow, "position:x", base_x + 6.0, 0.4)
	tw.tween_property(arrow, "position:x", base_x, 0.4)

	# texto ao lado do marcador
	var l := Label.new()
	l.text = "INÍCIO" if is_start else "FIM"
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(70, 26)
	if is_start:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.position = Vector2(x - 74, cy - 13)
	else:
		l.position = Vector2(x + PORT_W + 4, cy - 13)
	level_root.add_child(l)
	return r


# Caminho aleatório (DFS) da célula (0, start_row) até (cols-1, end_row)
func _make_path() -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var min_len := int(cols * rows * 0.45)
	for attempt in 40:
		var p: Array[Vector2i] = []
		_dfs(Vector2i(0, start_row), Vector2i(cols - 1, end_row), {}, p)
		if p.size() > best.size():
			best = p
		if best.size() >= min_len:
			break
	return best


func _dfs(cell: Vector2i, goal: Vector2i, visited: Dictionary, path: Array[Vector2i]) -> bool:
	visited[cell] = true
	path.append(cell)
	if cell == goal:
		return true
	var order := DIRS.duplicate()
	order.shuffle()
	for d in order:
		var n: Vector2i = cell + VEC[d]
		if _in_bounds(n) and not visited.has(n):
			if _dfs(n, goal, visited, path):
				return true
	path.pop_back()
	return false


func _dir_to(from: Vector2i, to: Vector2i) -> int:
	for d in DIRS:
		if VEC[d] == to - from:
			return d
	return 0


# ---------------------------------------------------------------- PEÇAS -----
func _make_tile(kind: int, x: int, y: int) -> Tile:
	var t := Tile.new()
	t.kind = kind
	t.node = Node2D.new()
	t.node.position = Vector2(x, y) * CELL + Vector2(CELL, CELL) / 2.0
	level_root.add_child(t.node)

	t.visual = Node2D.new()   # este nó é o que gira (em torno do centro da célula)
	t.node.add_child(t.visual)

	if kind == Kind.I:
		# sprite 32x32 empilhado 2x para cobrir os 64 px de altura da célula
		for oy in [-BELT_W / 2, BELT_W / 2]:
			var s := Sprite2D.new()
			s.texture = TEX_I
			s.position = Vector2(0, oy)
			t.visual.add_child(s)
	elif kind == Kind.L:
		# curva L 64x64: usamos só os 48x48 do canto, deslocado para centralizar a esteira
		var s := Sprite2D.new()
		s.texture = TEX_L
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(0, 0, L_CROP, L_CROP)
		s.position = Vector2(-MARGIN, -MARGIN)
		t.visual.add_child(s)
	else:
		# curva L2 (espelhada): braços na esquerda e embaixo -> usa x 16..64, y 0..48
		var s := Sprite2D.new()
		s.texture = TEX_L2
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(MARGIN, 0, L_CROP, L_CROP)
		s.position = Vector2(2 * MARGIN - CELL, -MARGIN)   # = (-32, -16)
		t.visual.add_child(s)
	return t


## Conexões da peça (bits) já considerando a rotação atual.
## Reta = CIMA|BAIXO.  Curva L = DIREITA|BAIXO.  Curva L2 (espelhada) = ESQUERDA|BAIXO.
func _tile_mask(t: Tile) -> int:
	var m: int
	match t.kind:
		Kind.I: m = UP | DOWN
		Kind.L: m = RIGHT | DOWN
		_: m = LEFT | DOWN
	for i in posmod(t.steps, 4):
		m = ((m << 1) | (m >> 3)) & 15   # gira 90° horário
	return m


func _mask_at(c: Vector2i) -> int:
	var t: Tile = grid[c.y][c.x]
	if t == null:
		return 0   # célula vazia não conecta com nada
	return _tile_mask(t)


func _opposite(d: int) -> int:
	return ((d << 2) | (d >> 2)) & 15


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


# ---------------------------------------------------------------- FLUXO -----
func _compute_flow() -> Dictionary:
	var powered := {}
	var solved := false
	var start := Vector2i(0, start_row)
	var goal := Vector2i(cols - 1, end_row)

	if (_mask_at(start) & LEFT) == 0:
		return {"powered": powered, "solved": false}

	var queue: Array[Vector2i] = [start]
	powered[start] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var m := _mask_at(c)
		if c == goal and (m & RIGHT) != 0:
			solved = true
		for d in DIRS:
			if (m & d) == 0:
				continue
			var n: Vector2i = c + VEC[d]
			if not _in_bounds(n) or powered.has(n):
				continue
			if (_mask_at(n) & _opposite(d)) != 0:
				powered[n] = true
				queue.append(n)
	return {"powered": powered, "solved": solved}


## Rota (lista de células, do início ao fim) que a mala vai percorrer.
## Usa busca em largura, então é o caminho mais curto dentro da rota do jogador.
func _find_route() -> Array[Vector2i]:
	var start := Vector2i(0, start_row)
	var goal := Vector2i(cols - 1, end_row)
	var parent := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == goal:
			break
		var m := _mask_at(c)
		for d in DIRS:
			if (m & d) == 0:
				continue
			var n: Vector2i = c + VEC[d]
			if not _in_bounds(n) or parent.has(n):
				continue
			if (_mask_at(n) & _opposite(d)) != 0:
				parent[n] = c
				queue.append(n)
	var route: Array[Vector2i] = []
	var cur := goal
	while cur != start:
		route.push_front(cur)
		cur = parent[cur]
	route.push_front(start)
	return route


func _refresh_flow() -> void:
	var res := _compute_flow()
	var powered: Dictionary = res["powered"]
	for y in rows:
		for x in cols:
			var t: Tile = grid[y][x]
			if t == null:
				continue
			t.visual.modulate = COLOR_POWERED if powered.has(Vector2i(x, y)) else Color.WHITE
	out_port.color = COLOR_OUT_ON if res["solved"] else COLOR_OUT_OFF
	if res["solved"] and state == State.PLAYING:
		_start_delivery()


# ---------------------------------------------------------------- MALA ------
func _make_suitcase() -> Node2D:
	var n := Node2D.new()
	n.z_index = 10
	if ResourceLoader.exists(MALA_PATH):
		var tex := load(MALA_PATH) as Texture2D
		var s := Sprite2D.new()
		s.texture = tex
		var big := maxf(tex.get_width(), tex.get_height())
		if big > MALA_MAX_SIZE:
			s.scale = Vector2.ONE * (MALA_MAX_SIZE / big)
		n.add_child(s)
	else:
		# placeholder até o sprite da mala existir
		var body := ColorRect.new()
		body.color = Color("#8b5a2b")
		body.size = Vector2(30, 22)
		body.position = Vector2(-15, -11)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_child(body)
		var handle := ColorRect.new()
		handle.color = Color("#3b2410")
		handle.size = Vector2(12, 5)
		handle.position = Vector2(-6, -16)
		handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_child(handle)
	return n


func _start_delivery() -> void:
	state = State.DELIVERING   # o tempo para e os cliques são ignorados
	var route := _find_route()
	var half := Vector2(CELL, CELL) / 2.0

	# pontos: fora do início -> centro de cada célula da rota -> fora do fim
	var points: Array[Vector2] = []
	points.append(Vector2(-PORT_W / 2.0, start_row * CELL + CELL / 2.0))
	for c in route:
		points.append(Vector2(c) * CELL + half)
	points.append(Vector2(cols * CELL + PORT_W / 2.0, end_row * CELL + CELL / 2.0))

	var suitcase := _make_suitcase()
	suitcase.position = points[0]
	level_root.add_child(suitcase)   # adicionada por último = desenhada por cima das esteiras

	var tw := suitcase.create_tween()
	for i in range(1, points.size()):
		var dur := points[i - 1].distance_to(points[i]) / DELIVERY_SPEED
		tw.tween_property(suitcase, "position", points[i], dur)
	tw.tween_callback(_finish_win)


func _finish_win() -> void:
	state = State.WON
	lock_until = Time.get_ticks_msec() + 500
	var bonus := 100 + int(time_left) * 10
	score += bonus
	var next_size := clampi(MIN_SIZE + level, MIN_SIZE, MAX_SIZE)
	_show_message("Nível %d completo!\n+%d pontos\n\nClique para continuar\n(próximo: %dx%d)" % [level, bonus, next_size, next_size])
	_update_hud()


# ---------------------------------------------------------------- JOGO ------
func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_lose()
	_update_hud()


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	match state:
		State.PLAYING:
			var p := board.get_local_mouse_position()
			var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			if not _in_bounds(c):
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				_rotate_tile(c, 1)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_rotate_tile(c, -1)
		State.WON:
			if Time.get_ticks_msec() >= lock_until:
				level += 1
				_new_level()
		State.LOST:
			if Time.get_ticks_msec() >= lock_until:
				level = 1
				score = 0
				_new_level()


func _rotate_tile(c: Vector2i, dir: int) -> void:
	var t: Tile = grid[c.y][c.x]
	if t == null:
		return   # clicar numa célula vazia não faz nada
	t.steps += dir
	if t.tween and t.tween.is_valid():
		t.tween.kill()
	t.tween = t.visual.create_tween()
	t.tween.tween_property(t.visual, "rotation", t.steps * PI / 2.0, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	moves += 1
	_refresh_flow()
	_update_hud()


func _lose() -> void:
	state = State.LOST
	lock_until = Time.get_ticks_msec() + 500
	_show_message("Tempo esgotado!\nPontuação final: %d\n\nClique para recomeçar" % score)


func _show_message(text: String) -> void:
	msg_label.text = text
	msg_label.visible = true
	dim.visible = true


func _update_hud() -> void:
	moves_label.text = "MOVIMENTOS: %d" % moves
	score_label.text = "PONTOS: %d" % score
	level_label.text = "NÍVEL: %d (%dx%d)" % [level, cols, rows]
	time_bar.max_value = time_total
	time_bar.value = time_left
