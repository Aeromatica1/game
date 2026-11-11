extends CanvasLayer
## Tela de escolha do tipo de área a alugar (lanchonete, livraria, cafeteria ou loja).
## O jogo fica pausado enquanto ela está aberta (mesmo comportamento da tela de questão).
##
## Uso:
##   var tela = get_tree().get_first_node_in_group("tela_escolha_area")
##   tela.escolhida.connect(func(tipo): ...)   # tipo = "lanchonete" | "livraria" | "cafeteria" | "loja"
##   tela.abrir()
##
## Para trocar/adicionar ícones ou opções, mexa só na constante OPCOES.

## Emitido quando o jogador escolhe um tipo de área. A tela já se fecha antes de emitir.
signal escolhida(tipo: String)
signal cancelada

## `icone`/`regiao`: imagem e recorte (em px) usados no cartão. Sem `icone` → cartão com "?".
const OPCOES := [
	{
		"tipo": "lanchonete", "nome": "Lanchonete",
		"icone": "res://assets/areas/lanchonete.png", "regiao": Rect2(38, 44, 528, 342),
	},
	{
		"tipo": "livraria", "nome": "Livraria",
		"icone": "res://assets/areas/livraria.png", "regiao": Rect2(146, 0, 558, 422),
	},
	{
		"tipo": "cafeteria", "nome": "Cafeteria",
		"icone": "res://assets/areas/cafeteria.png", "regiao": Rect2(180, 90, 450, 560),
	},
]

@export var fonte: Font
@export var cor_fundo: Color = Color(0.08, 0.11, 0.2)
@export var cor_borda: Color = Color(0.35, 0.6, 1.0)

var _aberta := false
var _titulo: Label
var _botoes: Array[Button] = []


func _ready() -> void:
	add_to_group("tela_escolha_area")
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	visible = false


func abrir(titulo: String = "Alugar espaço") -> void:
	if _aberta:
		return
	_titulo.text = titulo
	_aberta = true
	visible = true
	get_tree().paused = true
	_botoes[0].grab_focus()


func fechar() -> void:
	if not _aberta:
		return
	_aberta = false
	visible = false
	get_tree().paused = false


func _escolher(indice: int) -> void:
	if not _aberta:
		return
	var tipo: String = OPCOES[indice]["tipo"]
	fechar()
	escolhida.emit(tipo)


func _input(event: InputEvent) -> void:
	if not _aberta or not event is InputEventKey or not event.pressed or event.echo:
		return
	var escolha := -1
	match int(event.physical_keycode):
		KEY_1, KEY_KP_1: escolha = 0
		KEY_2, KEY_KP_2: escolha = 1
		KEY_3, KEY_KP_3: escolha = 2
		KEY_4, KEY_KP_4: escolha = 3
		KEY_ESCAPE, KEY_T:
			get_viewport().set_input_as_handled()
			fechar()
			cancelada.emit()
			return
	if escolha >= 0:
		# consome a tecla para a tela de questão (que abre em seguida) não tratá-la como resposta
		get_viewport().set_input_as_handled()
		_escolher(escolha)


# ------------------------------------------------------------------ construção da UI

func _construir() -> void:
	var tema := Theme.new()
	if fonte != null:
		tema.default_font = fonte
	tema.default_font_size = 22

	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.theme = tema
	add_child(raiz)

	var escuro := ColorRect.new()
	escuro.color = Color(0, 0, 0, 0.65)
	escuro.set_anchors_preset(Control.PRESET_FULL_RECT)
	escuro.mouse_filter = Control.MOUSE_FILTER_STOP
	raiz.add_child(escuro)

	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right"]:
		margem.add_theme_constant_override("margin_" + lado, 90)
	for lado in ["top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 70)
	raiz.add_child(margem)

	var painel := PanelContainer.new()
	painel.add_theme_stylebox_override("panel", _estilo(cor_fundo, cor_borda, 14, 3))
	margem.add_child(painel)

	var interno := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		interno.add_theme_constant_override("margin_" + lado, 24)
	painel.add_child(interno)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	interno.add_child(v)

	_titulo = Label.new()
	_titulo.add_theme_color_override("font_color", cor_borda.lightened(0.3))
	_titulo.add_theme_font_size_override("font_size", 28)
	v.add_child(_titulo)

	var sub := Label.new()
	sub.text = "Escolha o que este espaço do aeroporto vai se tornar:"
	sub.add_theme_color_override("font_color", Color(0.6, 0.68, 0.85))
	v.add_child(sub)

	v.add_child(HSeparator.new())

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 14)
	linha.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(linha)

	for i in OPCOES.size():
		var op: Dictionary = OPCOES[i]
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 250)
		b.text = "%d)  %s" % [i + 1, op["nome"]]
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_constant_override("icon_max_width", 220)
		b.add_theme_constant_override("h_separation", 0)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var icone := _icone(op)
		if icone != null:
			b.icon = icone
		else:
			b.text = "?\n\n%s\n(ícone em breve)" % b.text
		_pintar(b, Color(0.14, 0.19, 0.33), cor_borda.darkened(0.4))
		b.pressed.connect(_escolher.bind(i))
		linha.add_child(b)
		_botoes.append(b)

	var rodape := HBoxContainer.new()
	v.add_child(rodape)
	var dica := Label.new()
	dica.text = "Clique ou use as teclas 1 a 4"
	dica.add_theme_color_override("font_color", Color(0.6, 0.68, 0.85))
	dica.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rodape.add_child(dica)
	var cancelar := Button.new()
	cancelar.text = "Cancelar  (Esc)"
	cancelar.custom_minimum_size = Vector2(190, 44)
	cancelar.pressed.connect(func() -> void:
		fechar()
		cancelada.emit())
	rodape.add_child(cancelar)


func _icone(op: Dictionary) -> Texture2D:
	var caminho: String = op["icone"]
	if caminho == "" or not ResourceLoader.exists(caminho):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(caminho)
	atlas.region = op["regiao"]
	return atlas


func _estilo(fundo: Color, borda: Color, raio: int, largura: int) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = fundo
	e.border_color = borda
	e.set_border_width_all(largura)
	e.set_corner_radius_all(raio)
	e.content_margin_left = 14
	e.content_margin_right = 14
	e.content_margin_top = 14
	e.content_margin_bottom = 14
	return e


func _pintar(b: Button, fundo: Color, borda: Color) -> void:
	b.add_theme_stylebox_override("normal", _estilo(fundo, borda, 10, 2))
	b.add_theme_stylebox_override("hover", _estilo(fundo.lightened(0.15), borda.lightened(0.3), 10, 3))
	b.add_theme_stylebox_override("pressed", _estilo(fundo.darkened(0.15), borda, 10, 2))
	b.add_theme_stylebox_override("focus", _estilo(Color(0, 0, 0, 0), Color.WHITE, 10, 2))
