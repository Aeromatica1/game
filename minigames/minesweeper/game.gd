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
##  - cronômetro só começa no primeiro clique; contadores de 3 dígitos
##  - rosto que reinicia (sorrindo, "oh", morto, de óculos) e tecla F2
##  - ao perder: mostra minas, bandeiras erradas e a mina que explodiu
##  - ao ganhar: marca as minas restantes e grava o recorde (best time)

signal voltar_pressed

enum Cell { HIDDEN, FLAGGED, QUESTION, REVEALED }
enum State { READY, PLAYING, WON, LOST }

const Scores = preload("res://minigames/minesweeper/minesweeper_scores.gd")

const TEX_HIDDEN: Texture2D = preload("res://assets/minesweeper_minigame/hidden.png")
const TEX_SAFE: Texture2D = preload("res://assets/minesweeper_minigame/safe.png")
const TEX_FLAG: Texture2D = preload("res://assets/minesweeper_minigame/flag.png")
const TEX_MINE: Texture2D = preload("res://assets/minesweeper_minigame/mine.png")
const TEX_MINE_HIT: Texture2D = preload("res://assets/minesweeper_minigame/mine_selected.png")
## índice = quantidade de minas vizinhas (0 usa TEX_SAFE)
const NUMBER_TEXTURES = [
	null,
	preload("res://assets/minesweeper_minigame/1.png"),
	preload("res://assets/minesweeper_minigame/2.png"),
	preload("res://assets/minesweeper_minigame/3.png"),
	preload("res://assets/minesweeper_minigame/4.png"),
	preload("res://assets/minesweeper_minigame/5.png"),
	preload("res://assets/minesweeper_minigame/6.png"),
	preload("res://assets/minesweeper_minigame/7.png"),
	preload("res://assets/minesweeper_minigame/8.png"),
]
const MARK_FONT: Font = preload("res://assets/pixel_operator/PixelOperatorMono-Bold.ttf")

const COLOR_WRONG_FLAG := Color(1.0, 0.25, 0.25)
const COLOR_QUESTION := Color(0.92, 0.92, 0.92)
const COLOR_FACE := Color(1.0, 0.85, 0.15)

## dificuldades oficiais do Campo Minado
const CUSTOM := "custom"
const LEVELS := {
	"beginner": {"name": "Iniciante", "cols": 9, "rows": 9, "mines": 10},
	"intermediate": {"name": "Intermediário", "cols": 16, "rows": 16, "mines": 40},
	"expert": {"name": "Especialista", "cols": 30, "rows": 16, "mines": 99},
}
const CUSTOM_MIN_MINES := 10

const MAX_CELL_SIZE := 32.0
const MIN_CELL_SIZE := 12.0

@onready var back_button: Button = %BackButton
@onready var btn_beginner: Button = %BtnBeginner
@onready var btn_intermediate: Button = %BtnIntermediate
@onready var btn_expert: Button = %BtnExpert
@onready var btn_custom: Button = %BtnCustom
@onready var marks_check: CheckBox = %MarksCheck
@onready var records_button: Button = %RecordsButton

@onready var best_label: Label = %BestLabel
@onready var mines_label: Label = %MinesLabel
@onready var time_label: Label = %TimeLabel
@onready var status_label: Label = %StatusLabel
@onready var face: Control = %Face
@onready var board_area: Control = %BoardArea
@onready var board: Control = %Board

@onready var overlay: Control = %Overlay
@onready var dim: Control = %Dim
@onready var custom_panel: Control = %CustomPanel
@onready var cols_slider: HSlider = %ColsSlider
@onready var rows_slider: HSlider = %RowsSlider
@onready var mines_slider: HSlider = %MinesSlider
@onready var cols_value: Label = %ColsValue
@onready var rows_value: Label = %RowsValue
@onready var mines_value: Label = %MinesValue
@onready var custom_start: Button = %CustomStart
@onready var custom_cancel: Button = %CustomCancel
@onready var scores_panel: Control = %ScoresPanel
@onready var scores_text: Label = %ScoresText
@onready var reset_scores_button: Button = %ResetScoresButton
@onready var close_scores_button: Button = %CloseScoresButton

# configuração do jogo atual
var level_key: String = "beginner"
var cols: int = 9
var rows: int = 9
var mine_count: int = 10
var marks_enabled: bool = false

# estado do tabuleiro (arrays lineares: índice = linha * cols + coluna)
var mines := PackedByteArray()      # 1 = tem mina
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
var cell_size: float = MAX_CELL_SIZE
var hover: int = -1
var left_down: bool = false
var right_down: bool = false
var middle_down: bool = false
var chord_armed: bool = false       # o gesto atual é um chord
var chord_fired: bool = false       # o chord já foi executado neste gesto
var face_pressed: bool = false
var reset_armed: bool = false

var level_buttons: Dictionary = {}
var scores: Scores


func _ready() -> void:
	scores = Scores.new()
	marks_enabled = bool(scores.settings.get("marks", false))
	marks_check.set_pressed_no_signal(marks_enabled)

	level_buttons = {
		"beginner": btn_beginner,
		"intermediate": btn_intermediate,
		"expert": btn_expert,
		CUSTOM: btn_custom,
	}

	# tabuleiro e rosto
	board.draw.connect(_draw_board)
	board.gui_input.connect(_on_board_gui_input)
	board.mouse_exited.connect(_on_board_mouse_exited)
	board_area.resized.connect(_layout_board)
	face.draw.connect(_draw_face)
	face.gui_input.connect(_on_face_gui_input)

	# barra superior
	back_button.pressed.connect(func() -> void: voltar_pressed.emit())
	btn_beginner.pressed.connect(_start_level.bind("beginner"))
	btn_intermediate.pressed.connect(_start_level.bind("intermediate"))
	btn_expert.pressed.connect(_start_level.bind("expert"))
	btn_custom.pressed.connect(_open_custom)
	marks_check.toggled.connect(_on_marks_toggled)
	records_button.pressed.connect(_open_scores)

	# janelas (personalizado / recordes)
	dim.gui_input.connect(_on_dim_gui_input)
	cols_slider.value_changed.connect(_on_custom_slider_changed)
	rows_slider.value_changed.connect(_on_custom_slider_changed)
	mines_slider.value_changed.connect(_on_custom_slider_changed)
	custom_start.pressed.connect(_on_custom_start)
	custom_cancel.pressed.connect(_close_overlay)
	reset_scores_button.pressed.connect(_on_reset_scores_pressed)
	close_scores_button.pressed.connect(_close_overlay)

	_start_level("beginner")


# =============================================================================
#  Novo jogo
# =============================================================================

func _start_level(key: String) -> void:
	var cfg: Dictionary = LEVELS[key]
	level_key = key
	cols = int(cfg["cols"])
	rows = int(cfg["rows"])
	mine_count = int(cfg["mines"])
	new_game()


## Reinicia com a configuração atual (é o que o rosto e o F2 fazem).
func new_game() -> void:
	var total := cols * rows
	mines = _new_bytes(total)
	adjacent = _new_bytes(total)
	cells = _new_bytes(total)

	revealed_count = 0
	flag_count = 0
	exploded = -1
	elapsed = 0.0
	shown_seconds = -1
	state = State.READY
	status_text = ""

	hover = -1
	left_down = false
	right_down = false
	middle_down = false
	chord_armed = false
	chord_fired = false
	face_pressed = false

	_sync_level_buttons()
	_layout_board()
	_refresh_hud()
	board.queue_redraw()
	face.queue_redraw()


func _new_bytes(length: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(length)
	bytes.fill(0)
	return bytes


func _sync_level_buttons() -> void:
	var button: Button = level_buttons.get(level_key)
	if button != null:
		button.set_pressed_no_signal(true)


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
	status_text = "Perdeu!"


func _win() -> void:
	state = State.WON
	for i in cols * rows:
		if mines[i] == 1:
			cells[i] = Cell.FLAGGED
	flag_count = mine_count

	var ms := maxi(1, roundi(elapsed * 1000.0))
	status_text = "Venceu! %s" % _format_ms(ms)
	# só as dificuldades oficiais têm recorde (como no jogo original)
	if level_key != CUSTOM:
		var result: Dictionary = scores.submit(level_key, ms)
		if bool(result["new_record"]):
			status_text = "Novo recorde! %s" % _format_ms(ms)


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
	mines_label.text = "%03d" % (mine_count - flag_count)
	_refresh_time()
	status_label.text = status_text

	if level_key == CUSTOM:
		best_label.text = "Personalizado: sem recorde"
	else:
		var best := scores.best_ms(level_key)
		best_label.text = "Recorde: %s" % (_format_ms(best) if best > 0 else "--")


func _refresh_time() -> void:
	time_label.text = "%03d" % mini(int(elapsed), 999)


# =============================================================================
#  Tabuleiro: layout e desenho
# =============================================================================

func _layout_board() -> void:
	var area := board_area.size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	cell_size = clampf(floorf(minf(area.x / cols, area.y / rows)), MIN_CELL_SIZE, MAX_CELL_SIZE)
	board.size = Vector2(cols, rows) * cell_size
	board.position = ((area - board.size) * 0.5).floor()
	board.queue_redraw()


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
			tex = TEX_MINE_HIT
		elif mines[i] == 1 and cell != Cell.FLAGGED:
			tex = TEX_MINE
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
#  Rosto
# =============================================================================

func _draw_face() -> void:
	var box := face.size
	var center := box * 0.5
	var fr := minf(box.x, box.y) * 0.5 * 0.62

	# botão com chanfro (afundado enquanto está pressionado)
	var light := Color(0.62, 0.62, 0.62)
	var dark := Color(0.12, 0.12, 0.12)
	face.draw_rect(Rect2(Vector2.ZERO, box), Color(0.40, 0.40, 0.40))
	var top_left := dark if face_pressed else light
	var bottom_right := light if face_pressed else dark
	face.draw_rect(Rect2(0, 0, box.x, 3), top_left)
	face.draw_rect(Rect2(0, 0, 3, box.y), top_left)
	face.draw_rect(Rect2(0, box.y - 3, box.x, 3), bottom_right)
	face.draw_rect(Rect2(box.x - 3, 0, 3, box.y), bottom_right)

	face.draw_circle(center, fr, COLOR_FACE)
	face.draw_arc(center, fr, 0.0, TAU, 32, Color.BLACK, 2.0)

	var eye_y := center.y - fr * 0.25
	var eye_dx := fr * 0.38
	var smile_center := Vector2(center.x, center.y + fr * 0.05)

	if state == State.LOST:
		# olhos em X e boca triste
		var k := fr * 0.16
		for side in [-1.0, 1.0]:
			var e := Vector2(center.x + side * eye_dx, eye_y)
			face.draw_line(e + Vector2(-k, -k), e + Vector2(k, k), Color.BLACK, 2.0)
			face.draw_line(e + Vector2(-k, k), e + Vector2(k, -k), Color.BLACK, 2.0)
		face.draw_arc(Vector2(center.x, center.y + fr * 0.65), fr * 0.38, deg_to_rad(200), deg_to_rad(340), 12, Color.BLACK, 2.0)
	elif state == State.WON:
		# óculos escuros e sorriso
		face.draw_rect(Rect2(center.x - fr * 0.78, eye_y - fr * 0.22, fr * 1.56, fr * 0.1), Color.BLACK)
		for side in [-1.0, 1.0]:
			face.draw_rect(Rect2(center.x + side * eye_dx - fr * 0.27, eye_y - fr * 0.2, fr * 0.54, fr * 0.38), Color.BLACK)
		face.draw_arc(smile_center, fr * 0.55, deg_to_rad(25), deg_to_rad(155), 14, Color.BLACK, 2.0)
	elif _playable() and hover >= 0 and (left_down or middle_down):
		# "oh!" enquanto o botão está pressionado no tabuleiro
		for side in [-1.0, 1.0]:
			face.draw_circle(Vector2(center.x + side * eye_dx, eye_y), fr * 0.14, Color.BLACK)
		face.draw_circle(Vector2(center.x, center.y + fr * 0.42), fr * 0.16, Color.BLACK)
	else:
		for side in [-1.0, 1.0]:
			face.draw_circle(Vector2(center.x + side * eye_dx, eye_y), fr * 0.1, Color.BLACK)
		face.draw_arc(smile_center, fr * 0.55, deg_to_rad(25), deg_to_rad(155), 14, Color.BLACK, 2.0)


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
			new_game()


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
			if left_down or middle_down:
				board.queue_redraw()
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
#  Janelas: campo personalizado e recordes
# =============================================================================

func _max_mines(c: int, r: int) -> int:
	# mesmo limite do jogo original: no máximo (colunas-1) x (linhas-1)
	return (c - 1) * (r - 1)


func _open_custom() -> void:
	cols_slider.set_value_no_signal(cols)
	rows_slider.set_value_no_signal(rows)
	mines_slider.max_value = _max_mines(cols, rows)
	mines_slider.set_value_no_signal(mine_count)
	_update_custom_labels()
	overlay.show()
	custom_panel.show()
	scores_panel.hide()


func _on_custom_slider_changed(_value: float) -> void:
	var c := int(cols_slider.value)
	var r := int(rows_slider.value)
	mines_slider.max_value = _max_mines(c, r)
	_update_custom_labels()


func _update_custom_labels() -> void:
	cols_value.text = str(int(cols_slider.value))
	rows_value.text = str(int(rows_slider.value))
	mines_value.text = str(int(mines_slider.value))


func _on_custom_start() -> void:
	cols = int(cols_slider.value)
	rows = int(rows_slider.value)
	mine_count = clampi(int(mines_slider.value), CUSTOM_MIN_MINES, _max_mines(cols, rows))
	level_key = CUSTOM
	_close_overlay()
	new_game()


func _open_scores() -> void:
	reset_armed = false
	reset_scores_button.text = "Zerar recordes"
	_refresh_scores_text()
	overlay.show()
	scores_panel.show()
	custom_panel.hide()


func _refresh_scores_text() -> void:
	var lines := PackedStringArray()
	for key in LEVELS:
		lines.append(String(LEVELS[key]["name"]))
		var top := scores.top(key)
		if top.is_empty():
			lines.append("   --")
		for k in top.size():
			var entry: Dictionary = top[k]
			lines.append("  %d. %s   %s" % [k + 1, _format_ms(int(entry["time_ms"])).lpad(9), String(entry["date"])])
		lines.append("")
	scores_text.text = "\n".join(lines).strip_edges()


func _on_reset_scores_pressed() -> void:
	# confirmação em dois cliques para não apagar os recordes sem querer
	if not reset_armed:
		reset_armed = true
		reset_scores_button.text = "Confirmar?"
		return
	scores.reset()
	reset_armed = false
	reset_scores_button.text = "Zerar recordes"
	_refresh_scores_text()
	_refresh_hud()


func _close_overlay() -> void:
	overlay.hide()
	custom_panel.hide()
	scores_panel.hide()
	_sync_level_buttons()   # cancelar o "Personalizado" volta o destaque ao nível atual


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
		new_game()
		get_viewport().set_input_as_handled()
