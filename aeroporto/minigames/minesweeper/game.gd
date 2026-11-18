extends Control
## Campo Minado (Minesweeper) do Aeromática.
##
## O tabuleiro é desenhado por um único Control (_draw) e todo o input passa por
## ele. Isso permite o comportamento do jogo original:
##  - revelar ao SOLTAR o botão esquerdo (dá pra arrastar para fora e cancelar)
##  - botão direito alterna bandeira (e "?" se as marcas estiverem ligadas)
##  - "chording": esquerdo+direito juntos, ou botão do meio, num número já
##    revelado abre os vizinhos se a quantidade de bandeiras bater
##  - primeiro clique sempre seguro (e sempre abre uma região)
##  - modo progressivo: ao vencer, o próximo nível tem mais casas e mais minas.
##    A altura do tabuleiro é fixa e ele cresce pelos lados (uma coluna de cada lado)
##  - cronômetro só começa no primeiro clique; contadores de 3 dígitos
##  - policial que reinicia (clique nele ou tecla F2); ao lado dele, as minas restantes
##  - cronômetro com o tempo de jogo, no canto direito da moldura
##  - ao perder: mostra minas, bandeiras erradas e a mina que explodiu
##  - ao ganhar: marca as minas restantes e grava o recorde (best time)

signal voltar_pressed

enum Cell { HIDDEN, FLAGGED, QUESTION, REVEALED }
enum State { READY, PLAYING, WON, LOST }

const Scores = preload("res://aeroporto/minigames/minesweeper/minesweeper_scores.gd")

const PREFIX = "res://assets/minigames/minesweeper/"

const TEX_HIDDEN: Texture2D = preload(PREFIX + "hidden.png")
const TEX_HIDDEN_HOVER: Texture2D = preload(PREFIX + "hidden_hover.png")
const TEX_SAFE: Texture2D = preload(PREFIX + "safe.png")
const TEX_FLAG: Texture2D = preload(PREFIX + "flag.png")
const TEX_MINE: Texture2D = preload(PREFIX + "mine.png")
const TEX_MINE_HIT: Texture2D = preload(PREFIX + "mine_selected.png")

# Tipos de "mina": bomba, arma, faca e droga. Cada mina sorteia um tipo ao ser
# colocada (índice 0 = bomba, que é o mine.png padrão).
const MINE_TEXTURES = [
	TEX_MINE,
	preload(PREFIX + "mine_arma.png"),
	preload(PREFIX + "mine_faca.png"),
	preload(PREFIX + "mine_droga.png"),
]
const MINE_HIT_TEXTURES = [
	TEX_MINE_HIT,
	preload(PREFIX + "mine_arma_selected.png"),
	preload(PREFIX + "mine_faca_selected.png"),
	preload(PREFIX + "mine_droga_selected.png"),
]
## índice = quantidade de minas vizinhas (0 usa TEX_SAFE)
const NUMBER_TEXTURES = [
	null,
	preload(PREFIX + "1.png"),
	preload(PREFIX + "2.png"),
	preload(PREFIX + "3.png"),
	preload(PREFIX + "4.png"),
	preload(PREFIX + "5.png"),
	preload(PREFIX + "6.png"),
	preload(PREFIX + "7.png"),
	preload(PREFIX + "8.png"),
]
const MARK_FONT: Font = preload("res://assets/pixel_operator/PixelOperatorMono-Bold.ttf")

const COLOR_WRONG_FLAG := Color(1.0, 0.25, 0.25)
const COLOR_QUESTION := Color(0.92, 0.92, 0.92)
const COLOR_LED := Color(1.0, 0.15, 0.1)

## Moldura do tabuleiro (grid_frame.png): cabeçalho com o policial + contador de
## minas à esquerda e o cronômetro + tempo à direita. Medidas em pixels da imagem;
## a arte é ampliada em múltiplos inteiros (ver ui_scale) para ficar nítida.
const TEX_FRAME: Texture2D = preload(PREFIX + "grid_frame.png")
const FRAME_BORDER_X := 10.0          # borda esquerda / direita
const FRAME_HEADER_H := 23.0          # altura do cabeçalho
const FRAME_BORDER_BOTTOM := 10.0     # borda de baixo
const FRAME_HEAD_SIDE := 76.0         # largura de cada ponta do cabeçalho
const FRAME_MIN_WIDTH := FRAME_HEAD_SIDE * 2.0
const FRAME_FILL := Color8(16, 43, 70)
const FACE_RECT := Rect2(10, 1, 32, 22)          # área clicável do policial
const MINES_LED_RECT := Rect2(42, 3, 30, 18)     # número ao lado do policial
const TIME_LED_SIZE := Vector2(34, 18)           # número ao lado do cronômetro
const TIME_LED_FROM_RIGHT := 52.0                # distância da borda direita

## Modo progressivo. A altura é fixa (BASE_ROWS); a cada nível entram
## COLS_PER_LEVEL colunas (uma de cada lado) até MAX_COLS. Depois disso o tamanho
## para de crescer e só a densidade de minas continua subindo, até MAX_DENSITY.
const CELL_BASE := 32.0               # tamanho da casa na arte (px)
const BASE_COLS := 7
const BASE_ROWS := 7
const COLS_PER_LEVEL := 2
const MAX_COLS := 15
const BASE_DENSITY := 0.12            # minas / casas no nível 1
const DENSITY_PER_LEVEL := 0.012
const MAX_DENSITY := 0.22
const LEVEL_KEY := "level_%d"         # chave dos recordes de cada nível
const HINT_START := "Clique em uma casa para começar"

@onready var back_button: Button = %BackButton
@onready var marks_check: CheckBox = %MarksCheck
@onready var records_button: Button = %RecordsButton

@onready var best_label: Label = %BestLabel
@onready var status_label: Label = %StatusLabel
@onready var next_button: Button = %NextButton
@onready var face: Control = %Face
@onready var board_area: Control = %BoardArea
@onready var frame: Control = %Frame
@onready var board: Control = %Board

@onready var overlay: Control = %Overlay
@onready var dim: Control = %Dim
@onready var scores_panel: Control = %ScoresPanel
@onready var scores_text: Label = %ScoresText
@onready var reset_scores_button: Button = %ResetScoresButton
@onready var close_scores_button: Button = %CloseScoresButton

# configuração do jogo atual
var level: int = 1
var cols: int = BASE_COLS
var rows: int = BASE_ROWS
var mine_count: int = 6
var marks_enabled: bool = false

# estado do tabuleiro (arrays lineares: índice = linha * cols + coluna)
var mines := PackedByteArray()      # 1 = tem mina
var mine_kind := PackedByteArray()  # tipo visual da mina (índice em MINE_TEXTURES)
var adjacent := PackedByteArray()   # minas vizinhas
var cells := PackedByteArray()      # valores de Cell
var exploded: int = -1              # mina que o jogador acionou
var revealed_count: int = 0
var flag_count: int = 0

var state: State = State.READY
var elapsed: float = 0.0            # segundos de jogo (só conta com a tela visível)
var shown_seconds: int = -1
var status_text: String = ""

# input
var cell_size: float = CELL_BASE
var ui_scale: int = 1               # ampliação inteira da arte (casas = 32 * ui_scale px)
var mines_text := "000"
var time_text := "000"
var _mines_led := Rect2()           # caixas dos números dentro da moldura
var _time_led := Rect2()
var hover: int = -1
var left_down: bool = false
var right_down: bool = false
var middle_down: bool = false
var chord_armed: bool = false       # o gesto atual é um chord
var chord_fired: bool = false       # o chord já foi executado neste gesto
var face_pressed: bool = false
var reset_armed: bool = false

var scores: Scores


func _ready() -> void:
	scores = Scores.new()
	marks_enabled = bool(scores.settings.get("marks", false))
	marks_check.set_pressed_no_signal(marks_enabled)

	# tabuleiro e rosto
	frame.draw.connect(_draw_frame)
	board.draw.connect(_draw_board)
	board.gui_input.connect(_on_board_gui_input)
	board.mouse_exited.connect(_on_board_mouse_exited)
	board_area.resized.connect(_layout_board)
	face.draw.connect(_draw_face)
	face.gui_input.connect(_on_face_gui_input)

	# barra superior
	back_button.pressed.connect(func() -> void: voltar_pressed.emit())
	next_button.pressed.connect(_restart_or_advance)
	marks_check.toggled.connect(_on_marks_toggled)
	records_button.pressed.connect(_open_scores)

	# janela de recordes
	dim.gui_input.connect(_on_dim_gui_input)
	reset_scores_button.pressed.connect(_on_reset_scores_pressed)
	close_scores_button.pressed.connect(_close_overlay)

	_start_level(1)


# =============================================================================
#  Novo jogo
# =============================================================================

func _start_level(n: int) -> void:
	level = maxi(1, n)
	var cfg := _level_config(level)
	cols = int(cfg["cols"])
	rows = int(cfg["rows"])
	mine_count = int(cfg["mines"])
	new_game()


## Tamanho e minas de cada nível: altura fixa, colunas crescendo de 2 em 2 (uma de
## cada lado) até MAX_COLS e densidade de minas subindo até MAX_DENSITY.
func _level_config(n: int) -> Dictionary:
	var c := mini(BASE_COLS + COLS_PER_LEVEL * (n - 1), MAX_COLS)
	var r := BASE_ROWS
	var density := minf(BASE_DENSITY + DENSITY_PER_LEVEL * (n - 1), MAX_DENSITY)
	var m := clampi(roundi(c * r * density), 1, c * r - 9)
	return {"cols": c, "rows": r, "mines": m}


## Policial, F2 e botão "Próximo nível": depois de vencer sobe de nível,
## nos outros casos recomeça o nível atual.
func _restart_or_advance() -> void:
	if state == State.WON:
		_start_level(level + 1)
	else:
		new_game()


## Reinicia o nível atual.
func new_game() -> void:
	var total := cols * rows
	mines = _new_bytes(total)
	mine_kind = _new_bytes(total)
	adjacent = _new_bytes(total)
	cells = _new_bytes(total)

	revealed_count = 0
	flag_count = 0
	exploded = -1
	elapsed = 0.0
	shown_seconds = -1
	state = State.READY
	status_text = HINT_START

	hover = -1
	left_down = false
	right_down = false
	middle_down = false
	chord_armed = false
	chord_fired = false
	face_pressed = false

	_layout_board()
	_refresh_hud()
	board.queue_redraw()
	face.queue_redraw()


func _new_bytes(length: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(length)
	bytes.fill(0)
	return bytes


# =============================================================================
#  Regras
# =============================================================================

func _playable() -> bool:
	return state == State.READY or state == State.PLAYING


func _row(i: int) -> int:
	return floori(i / float(cols))


func _col(i: int) -> int:
	return i % cols


func _neighbors(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := _row(i)
	var c := _col(i)
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr := r + dr
			var nc := c + dc
			if nr >= 0 and nr < rows and nc >= 0 and nc < cols:
				out.append(nr * cols + nc)
	return out


## As minas só são sorteadas no primeiro clique: a casa clicada e seus vizinhos
## ficam livres, então o primeiro clique nunca perde e sempre abre uma região.
func _place_mines(first: int) -> void:
	var total := cols * rows
	mine_count = mini(mine_count, total - 1)

	var blocked := {first: true}
	for nb in _neighbors(first):
		blocked[nb] = true

	var candidates: Array[int] = []
	for i in total:
		if not blocked.has(i):
			candidates.append(i)
	# tabuleiro quase cheio de minas: protege só a casa clicada
	if candidates.size() < mine_count:
		candidates.clear()
		for i in total:
			if i != first:
				candidates.append(i)

	candidates.shuffle()
	for k in mine_count:
		mines[candidates[k]] = 1
		mine_kind[candidates[k]] = randi() % MINE_TEXTURES.size()

	for i in total:
		if mines[i] == 1:
			continue
		var count := 0
		for nb in _neighbors(i):
			count += mines[nb]
		adjacent[i] = count


## Revela uma casa escondida/marcada com "?" (o primeiro clique sorteia as minas).
func _reveal_cell(i: int) -> void:
	if state == State.READY:
		_place_mines(i)
		state = State.PLAYING
		status_text = ""
		elapsed = 0.0
	if mines[i] == 1:
		_lose(i)
	else:
		_flood_reveal(i)


## Abre a casa e, se for um zero, todas as vizinhas (iterativo: sem estouro de
## pilha em tabuleiros grandes). Casas com bandeira nunca são abertas.
func _flood_reveal(start: int) -> void:
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if cells[i] == Cell.REVEALED or cells[i] == Cell.FLAGGED:
			continue
		cells[i] = Cell.REVEALED
		revealed_count += 1
		if adjacent[i] != 0:
			continue
		for nb in _neighbors(i):
			if cells[nb] == Cell.HIDDEN or cells[nb] == Cell.QUESTION:
				stack.append(nb)


## Chord: num número revelado cuja contagem de bandeiras vizinhas é igual ao
## número, abre todas as vizinhas que não têm bandeira (pode explodir).
func _chord(i: int) -> void:
	if state != State.PLAYING or cells[i] != Cell.REVEALED or adjacent[i] == 0:
		return
	var flags := 0
	var targets: Array[int] = []
	for nb in _neighbors(i):
		if cells[nb] == Cell.FLAGGED:
			flags += 1
		elif cells[nb] == Cell.HIDDEN or cells[nb] == Cell.QUESTION:
			targets.append(nb)
	if flags != adjacent[i]:
		return
	for t in targets:
		if state != State.PLAYING:
			break
		if cells[t] == Cell.HIDDEN or cells[t] == Cell.QUESTION:
			_reveal_cell(t)
	_check_win()


## Bandeira -> ("?" se as marcas estiverem ligadas) -> vazio.
func _toggle_mark(i: int) -> void:
	match cells[i]:
		Cell.HIDDEN:
			cells[i] = Cell.FLAGGED
			flag_count += 1
		Cell.FLAGGED:
			flag_count -= 1
			cells[i] = Cell.QUESTION if marks_enabled else Cell.HIDDEN
		Cell.QUESTION:
			cells[i] = Cell.HIDDEN


func _check_win() -> void:
	if state == State.PLAYING and revealed_count == cols * rows - mine_count:
		_win()


func _lose(hit: int) -> void:
	state = State.LOST
	exploded = hit
	status_text = "Perdeu! Clique no policial (ou F2) para tentar de novo"


func _win() -> void:
	state = State.WON
	for i in cols * rows:
		if mines[i] == 1:
			cells[i] = Cell.FLAGGED
	flag_count = mine_count

	var ms := maxi(1, roundi(elapsed * 1000.0))
	status_text = "Nível %d concluído! %s" % [level, _format_ms(ms)]
	var result: Dictionary = scores.submit(LEVEL_KEY % level, ms)
	if bool(result["new_record"]):
		status_text = "Nível %d concluído! Novo recorde: %s" % [level, _format_ms(ms)]
	if level > int(scores.settings.get("best_level", 0)):
		scores.settings["best_level"] = level
		scores.save_to_disk()


# =============================================================================
#  Tempo
# =============================================================================

func _process(delta: float) -> void:
	# o cronômetro para se a tela estiver escondida ou com uma janela aberta
	if state != State.PLAYING or overlay.visible or not is_visible_in_tree():
		return
	elapsed += delta
	var secs := mini(int(elapsed), 999)
	if secs != shown_seconds:
		shown_seconds = secs
		_refresh_time()


func _format_ms(ms: int) -> String:
	return "%.2f s" % (ms / 1000.0)


# =============================================================================
#  HUD
# =============================================================================

func _refresh_hud() -> void:
	mines_text = "%03d" % (mine_count - flag_count)
	_refresh_time()
	status_label.text = status_text
	next_button.visible = state == State.WON

	var best := scores.best_ms(LEVEL_KEY % level)
	var best_text := _format_ms(best) if best > 0 else "--"
	best_label.text = "Nível %d  ·  %d×%d  ·  %d minas  ·  Recorde: %s" % [level, cols, rows, mine_count, best_text]


func _refresh_time() -> void:
	time_text = "%03d" % mini(int(elapsed), 999)
	frame.queue_redraw()


# =============================================================================
#  Tabuleiro: layout e desenho
# =============================================================================

## Escala inteira da arte: a maior em que o nível mais largo ainda cabe na área.
## Assim as casas têm tamanho fixo (32 * escala) e o tabuleiro só cresce pelos lados.
func _pick_scale(area: Vector2) -> int:
	var sc := 3
	while sc > 1:
		var need_w := (MAX_COLS * CELL_BASE + FRAME_BORDER_X * 2.0) * sc
		var need_h := (BASE_ROWS * CELL_BASE + FRAME_HEADER_H + FRAME_BORDER_BOTTOM) * sc
		if area.x >= need_w and area.y >= need_h:
			return sc
		sc -= 1
	return 1


func _layout_board() -> void:
	var area := board_area.size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	ui_scale = _pick_scale(area)
	var sc := float(ui_scale)
	cell_size = CELL_BASE * sc
	board.size = Vector2(cols, rows) * cell_size

	# a moldura fica centralizada: quando entram colunas, ela abre para os dois lados
	var bx := FRAME_BORDER_X * sc
	var hh := FRAME_HEADER_H * sc
	var frame_w := maxf(board.size.x + bx * 2.0, FRAME_MIN_WIDTH * sc)
	frame.size = Vector2(frame_w, board.size.y + hh + FRAME_BORDER_BOTTOM * sc)
	frame.position = Vector2(
		floorf((area.x - frame.size.x) * 0.5),
		maxf(0.0, floorf((area.y - frame.size.y) * 0.5)))
	board.position = frame.position + Vector2(floorf((frame_w - board.size.x) * 0.5), hh)

	# policial e números ficam dentro do cabeçalho da moldura
	face.position = FACE_RECT.position * sc
	face.size = FACE_RECT.size * sc
	_mines_led = Rect2(MINES_LED_RECT.position * sc, MINES_LED_RECT.size * sc)
	_time_led = Rect2(
		Vector2(frame_w - TIME_LED_FROM_RIGHT * sc, MINES_LED_RECT.position.y * sc),
		TIME_LED_SIZE * sc)

	frame.queue_redraw()
	board.queue_redraw()
	face.queue_redraw()


## Desenha a moldura esticando só o miolo do cabeçalho, as bordas e o rodapé
## (a arte é ampliada por ui_scale), então ela serve para qualquer largura.
func _draw_frame() -> void:
	var sc := float(ui_scale)
	var w := frame.size.x
	var h := frame.size.y
	var bx := FRAME_BORDER_X * sc
	var hh := FRAME_HEADER_H * sc
	var bb := FRAME_BORDER_BOTTOM * sc
	var side := FRAME_HEAD_SIDE * sc
	var body_h := h - hh - bb

	# fundo atrás do tabuleiro
	frame.draw_rect(Rect2(bx, hh, w - bx * 2.0, body_h), FRAME_FILL)

	# cabeçalho: ponta do policial | miolo esticado | ponta do cronômetro
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(0, 0, side, hh), Rect2(14, 0, FRAME_HEAD_SIDE, FRAME_HEADER_H))
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(side, 0, w - side * 2.0, hh), Rect2(90, 0, 125, FRAME_HEADER_H))
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(w - side, 0, side, hh), Rect2(215, 0, FRAME_HEAD_SIDE, FRAME_HEADER_H))

	# bordas laterais
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(0, hh, bx, body_h), Rect2(14, 24, 10, 255))
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(w - bx, hh, bx, body_h), Rect2(281, 24, 10, 255))

	# rodapé: canto | miolo esticado | canto
	var by := h - bb
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(0, by, bx, bb), Rect2(14, 280, 10, 10))
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(bx, by, w - bx * 2.0, bb), Rect2(24, 280, 257, 10))
	frame.draw_texture_rect_region(TEX_FRAME, Rect2(w - bx, by, bx, bb), Rect2(281, 280, 10, 10))

	# números: minas restantes (ao lado do policial) e tempo (ao lado do cronômetro)
	_draw_led(_mines_led, mines_text)
	_draw_led(_time_led, time_text)


func _draw_led(box: Rect2, text: String) -> void:
	var fs := 16 * ui_scale
	var ascent := MARK_FONT.get_ascent(fs)
	var descent := MARK_FONT.get_descent(fs)
	var y := box.position.y + (box.size.y - (ascent + descent)) * 0.5 + ascent
	frame.draw_string(MARK_FONT, Vector2(box.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs, COLOR_LED)


func _draw_board() -> void:
	var cell_vec := Vector2(cell_size, cell_size)
	for r in rows:
		for c in cols:
			_draw_cell(r * cols + c, Rect2(Vector2(c, r) * cell_size, cell_vec))


func _revealed_texture(i: int) -> Texture2D:
	var n: int = adjacent[i]
	if n > 0:
		return NUMBER_TEXTURES[n]
	return TEX_SAFE


func _draw_cell(i: int, rect: Rect2) -> void:
	var cell: int = cells[i]
	var tex: Texture2D = TEX_HIDDEN
	var question := false
	var wrong_flag := false

	if state == State.LOST:
		if i == exploded:
			tex = MINE_HIT_TEXTURES[mine_kind[i]]
		elif mines[i] == 1 and cell != Cell.FLAGGED:
			tex = MINE_TEXTURES[mine_kind[i]]
		elif cell == Cell.FLAGGED:
			if mines[i] == 1:
				tex = TEX_FLAG
			else:
				tex = TEX_MINE
				wrong_flag = true   # bandeira em casa sem mina
		elif cell == Cell.REVEALED:
			tex = _revealed_texture(i)
		elif cell == Cell.QUESTION:
			question = true
	else:
		if cell == Cell.REVEALED:
			tex = _revealed_texture(i)
		elif cell == Cell.FLAGGED:
			tex = TEX_FLAG
		elif cell == Cell.QUESTION:
			question = true
		# casa "afundada" enquanto o botão está pressionado
		if (cell == Cell.HIDDEN or cell == Cell.QUESTION) and _is_pressed_preview(i):
			tex = TEX_SAFE
			question = false

	# casa fechada sob o mouse fica mais clara: mostra que dá para clicar
	if tex == TEX_HIDDEN and i == hover and _playable() and not left_down:
		tex = TEX_HIDDEN_HOVER

	board.draw_texture_rect(tex, rect, false)

	if wrong_flag:
		var m := cell_size * 0.18
		var w := maxf(2.0, cell_size * 0.09)
		board.draw_line(rect.position + Vector2(m, m), rect.end - Vector2(m, m), COLOR_WRONG_FLAG, w)
		board.draw_line(Vector2(rect.position.x + m, rect.end.y - m), Vector2(rect.end.x - m, rect.position.y + m), COLOR_WRONG_FLAG, w)
	if question:
		var base := Vector2(rect.position.x, rect.position.y + cell_size * 0.76)
		board.draw_string(MARK_FONT, base, "?", HORIZONTAL_ALIGNMENT_CENTER, cell_size, int(cell_size * 0.75), COLOR_QUESTION)


func _is_near(i: int, j: int) -> bool:
	return absi(_row(i) - _row(j)) <= 1 and absi(_col(i) - _col(j)) <= 1


func _is_pressed_preview(i: int) -> bool:
	if hover < 0 or not _playable():
		return false
	if middle_down or (left_down and right_down):
		return _is_near(i, hover)
	return left_down and i == hover


# =============================================================================
#  Policial (botão de novo jogo)
# =============================================================================

## O desenho do policial já está na moldura; aqui só escurece enquanto o botão
## está pressionado.
func _draw_face() -> void:
	if face_pressed:
		face.draw_rect(Rect2(Vector2.ZERO, face.size), Color(0, 0, 0, 0.3))


func _on_face_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		face_pressed = true
		face.queue_redraw()
	else:
		var inside := Rect2(Vector2.ZERO, face.size).has_point(mb.position)
		face_pressed = false
		face.queue_redraw()
		if inside:
			_restart_or_advance()


# =============================================================================
#  Input do tabuleiro
# =============================================================================

func _cell_at(pos: Vector2) -> int:
	if pos.x < 0.0 or pos.y < 0.0:
		return -1
	var c := int(pos.x / cell_size)
	var r := int(pos.y / cell_size)
	if c >= cols or r >= rows:
		return -1
	return r * cols + c


func _on_board_mouse_exited() -> void:
	if hover != -1:
		hover = -1
		board.queue_redraw()
		face.queue_redraw()


func _on_board_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var h := _cell_at(motion.position)
		if h != hover:
			hover = h
			board.queue_redraw()
			if left_down or middle_down:
				face.queue_redraw()
		return

	var mb := event as InputEventMouseButton
	if mb == null:
		return
	var button := mb.button_index
	if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT and button != MOUSE_BUTTON_MIDDLE:
		return

	hover = _cell_at(mb.position)
	if mb.pressed:
		_on_button_down(button, hover)
	else:
		_on_button_up(button, hover)

	_refresh_hud()
	board.queue_redraw()
	face.queue_redraw()


func _on_button_down(button: int, idx: int) -> void:
	match button:
		MOUSE_BUTTON_LEFT:
			left_down = true
		MOUSE_BUTTON_RIGHT:
			right_down = true
		MOUSE_BUTTON_MIDDLE:
			middle_down = true
	if not _playable():
		return

	if middle_down or (left_down and right_down):
		chord_armed = true
	elif button == MOUSE_BUTTON_RIGHT and idx >= 0 and not chord_armed:
		_toggle_mark(idx)


func _on_button_up(button: int, idx: int) -> void:
	var was_chord := chord_armed
	match button:
		MOUSE_BUTTON_LEFT:
			left_down = false
		MOUSE_BUTTON_RIGHT:
			right_down = false
		MOUSE_BUTTON_MIDDLE:
			middle_down = false

	if _playable() and idx >= 0:
		if was_chord:
			# o chord é executado na primeira soltura do gesto
			if not chord_fired:
				chord_fired = true
				_chord(idx)
		elif button == MOUSE_BUTTON_LEFT:
			if cells[idx] == Cell.HIDDEN or cells[idx] == Cell.QUESTION:
				_reveal_cell(idx)
				_check_win()

	if not (left_down or right_down or middle_down):
		chord_armed = false
		chord_fired = false


# =============================================================================
#  Marcas (?)
# =============================================================================

func _on_marks_toggled(enabled: bool) -> void:
	marks_enabled = enabled
	scores.settings["marks"] = enabled
	scores.save_to_disk()
	if not enabled:
		for i in cells.size():
			if cells[i] == Cell.QUESTION:
				cells[i] = Cell.HIDDEN
		board.queue_redraw()


# =============================================================================
#  Janela de recordes
# =============================================================================

func _open_scores() -> void:
	reset_armed = false
	reset_scores_button.text = "Zerar recordes"
	_refresh_scores_text()
	overlay.show()
	scores_panel.show()


func _refresh_scores_text() -> void:
	var lines := PackedStringArray()
	lines.append("Maior nível concluído: %d" % int(scores.settings.get("best_level", 0)))
	lines.append("")

	var levels: Array[int] = []
	for key in scores.level_keys():
		var key_text := String(key)
		if key_text.begins_with("level_"):
			levels.append(int(key_text.substr(6)))
	levels.sort()

	if levels.is_empty():
		lines.append("   --")
	for n in levels:
		var cfg := _level_config(n)
		var top := scores.top(LEVEL_KEY % n)
		if top.is_empty():
			continue
		var entry: Dictionary = top[0]
		lines.append("Nível %2d  %2d×%d  %s   %s" % [n, cfg["cols"], cfg["rows"], _format_ms(int(entry["time_ms"])).lpad(9), String(entry["date"])])
	scores_text.text = "\n".join(lines).strip_edges()


func _on_reset_scores_pressed() -> void:
	# confirmação em dois cliques para não apagar os recordes sem querer
	if not reset_armed:
		reset_armed = true
		reset_scores_button.text = "Confirmar?"
		return
	scores.reset()
	scores.settings["best_level"] = 0
	scores.save_to_disk()
	reset_armed = false
	reset_scores_button.text = "Zerar recordes"
	_refresh_scores_text()
	_refresh_hud()


func _close_overlay() -> void:
	overlay.hide()
	scores_panel.hide()


func _on_dim_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_overlay()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F2 and not overlay.visible:
		_restart_or_advance()
		get_viewport().set_input_as_handled()
