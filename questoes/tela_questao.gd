extends CanvasLayer
## Tela de questão de múltipla escolha (enunciado + 4 alternativas).
## O jogo fica pausado enquanto ela está aberta.
##
## Uso:
##   var tela = get_tree().get_first_node_in_group("tela_questao")
##   tela.abrir(questao, "Atendente • Check-in")      # `questao` no formato de banco_questoes.gd
##   tela.resposta_escolhida.connect(...)             # recebe a escolha do jogador
##
## Com `questao` vazio mostra só o espaço em branco (placeholders).

## Emitido quando o jogador escolhe uma alternativa.
## `acertou` é true/false se a questão tem gabarito, ou null se `correta` = -1/ausente.
signal resposta_escolhida(questao: Dictionary, indice: int, acertou: Variant)
signal fechada(respondida: bool)

@export var fonte: Font = preload("res://assets/pixel_operator/PixelOperator.ttf")
@export var cor_fundo: Color = Color(0.08, 0.11, 0.2)
@export var cor_borda: Color = Color(0.35, 0.6, 1.0)

const LETRAS := ["A", "B", "C", "D"]
const PLACEHOLDER_ENUNCIADO := "Espaço reservado para a pergunta matemática."

var _questao: Dictionary = {}
var _respondida := false
var _aberta := false

var _titulo: Label
var _id_label: Label
var _enunciado: RichTextLabel
var _botoes: Array[Button] = []
var _feedback: Label
var _fechar: Button


func _ready() -> void:
	add_to_group("tela_questao")
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	visible = false


func abrir(questao: Dictionary = {}, titulo: String = "") -> void:
	_questao = questao
	_respondida = false
	_titulo.text = titulo if titulo != "" else "Questão"
	_id_label.text = ("Questão #%s" % str(questao["id"])) if questao.has("id") else ""

	var enunciado := String(questao.get("enunciado", ""))
	_enunciado.text = enunciado if enunciado != "" else "[color=#8a97b5][i]%s[/i][/color]" % PLACEHOLDER_ENUNCIADO
	var alts: Array = questao.get("alternativas", [])
	for i in 4:
		var b := _botoes[i]
		var texto := String(alts[i]) if i < alts.size() else "Alternativa %s" % LETRAS[i]
		b.text = "%s)  %s" % [LETRAS[i], texto]
		b.disabled = false
		_pintar(b, Color(0.14, 0.19, 0.33), cor_borda.darkened(0.4))
	_feedback.text = ""
	_fechar.text = "Fechar  (Esc)"

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
	fechada.emit(_respondida)


func _input(event: InputEvent) -> void:
	if not _aberta or not event is InputEventKey or not event.pressed or event.echo:
		return
	var tecla: int = event.physical_keycode
	var escolha := -1
	match tecla:
		KEY_1, KEY_KP_1, KEY_A: escolha = 0
		KEY_2, KEY_KP_2, KEY_B: escolha = 1
		KEY_3, KEY_KP_3, KEY_C: escolha = 2
		KEY_4, KEY_KP_4, KEY_D: escolha = 3
		KEY_ESCAPE:
			fechar()
			get_viewport().set_input_as_handled()
			return
	if escolha >= 0 and not _respondida:
		_escolher(escolha)
		get_viewport().set_input_as_handled()


func _escolher(indice: int) -> void:
	if _respondida:
		return
	_respondida = true
	var correta := int(_questao.get("correta", -1))
	var tem_gabarito := correta >= 0 and correta < 4
	for i in 4:
		_botoes[i].disabled = true
	if tem_gabarito:
		var acertou := indice == correta
		_pintar(_botoes[correta], Color(0.12, 0.45, 0.22), Color(0.4, 0.9, 0.5))
		if not acertou:
			_pintar(_botoes[indice], Color(0.55, 0.15, 0.18), Color(1.0, 0.45, 0.45))
		_feedback.text = "Correto!" if acertou else "Resposta incorreta."
		_feedback.add_theme_color_override("font_color", Color(0.5, 1, 0.6) if acertou else Color(1, 0.55, 0.55))
		resposta_escolhida.emit(_questao, indice, acertou)
	else:
		_pintar(_botoes[indice], Color(0.2, 0.3, 0.6), cor_borda)
		_feedback.text = "Resposta registrada."
		_feedback.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
		resposta_escolhida.emit(_questao, indice, null)
	_fechar.text = "Continuar  (Esc)"
	_fechar.grab_focus()


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
		margem.add_theme_constant_override("margin_" + lado, 50)
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

	var cab := HBoxContainer.new()
	v.add_child(cab)
	_titulo = Label.new()
	_titulo.add_theme_color_override("font_color", cor_borda.lightened(0.3))
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(_titulo)
	_id_label = Label.new()
	_id_label.add_theme_color_override("font_color", Color(0.6, 0.68, 0.85))
	cab.add_child(_id_label)

	v.add_child(HSeparator.new())

	# espaço da pergunta
	var caixa := PanelContainer.new()
	caixa.custom_minimum_size = Vector2(0, 170)
	caixa.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caixa.add_theme_stylebox_override("panel", _estilo(Color(0.05, 0.07, 0.14), cor_borda.darkened(0.5), 10, 2))
	v.add_child(caixa)
	var m2 := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		m2.add_theme_constant_override("margin_" + lado, 18)
	caixa.add_child(m2)
	_enunciado = RichTextLabel.new()
	_enunciado.bbcode_enabled = true
	_enunciado.fit_content = false
	_enunciado.scroll_active = true
	_enunciado.add_theme_font_size_override("normal_font_size", 28)
	_enunciado.add_theme_font_size_override("italics_font_size", 28)
	m2.add_child(_enunciado)

	# alternativas (2x2)
	var grade := GridContainer.new()
	grade.columns = 2
	grade.add_theme_constant_override("h_separation", 14)
	grade.add_theme_constant_override("v_separation", 14)
	v.add_child(grade)
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 78)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(_escolher.bind(i))
		grade.add_child(b)
		_botoes.append(b)

	var rodape := HBoxContainer.new()
	v.add_child(rodape)
	_feedback = Label.new()
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rodape.add_child(_feedback)
	_fechar = Button.new()
	_fechar.custom_minimum_size = Vector2(190, 44)
	_fechar.pressed.connect(fechar)
	rodape.add_child(_fechar)


func _estilo(fundo: Color, borda: Color, raio: int, largura: int) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = fundo
	e.border_color = borda
	e.set_border_width_all(largura)
	e.set_corner_radius_all(raio)
	e.content_margin_left = 14
	e.content_margin_right = 14
	return e


## Aplica a mesma cor nos estados normal/hover/pressed/disabled (o disabled não "apaga" o botão).
func _pintar(b: Button, fundo: Color, borda: Color) -> void:
	b.add_theme_stylebox_override("normal", _estilo(fundo, borda, 10, 2))
	b.add_theme_stylebox_override("hover", _estilo(fundo.lightened(0.15), borda.lightened(0.3), 10, 3))
	b.add_theme_stylebox_override("pressed", _estilo(fundo.darkened(0.15), borda, 10, 2))
	b.add_theme_stylebox_override("focus", _estilo(Color(0, 0, 0, 0), Color.WHITE, 10, 2))
	b.add_theme_stylebox_override("disabled", _estilo(fundo, borda, 10, 2))
	b.add_theme_color_override("font_disabled_color", Color(0.92, 0.94, 1))
