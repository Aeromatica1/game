extends CanvasLayer
## Tela de escolha do tipo de estabelecimento a instalar numa área alugável.
## O jogo fica pausado enquanto ela está aberta (mesmo comportamento da tela de questão).
##
## As opções vêm do banco (`GameState.tipos_aluguel`: descrição, preço, renda e nível mínimo);
## `OPCOES` só liga cada descrição ao ícone. Sem dados do banco (cena aberta direto), mostra as
## opções de `OPCOES` sem preço. Tipo do banco sem ícone vira um cartão com "?".
##
## Uso:
##   var tela = get_tree().get_first_node_in_group("tela_escolha_area")
##   tela.escolhida.connect(func(tipo, tipo_aluguel_id): ...)   # id = -1 se não veio do banco
##   tela.abrir()

## Emitido quando o jogador escolhe um tipo. A tela já se fecha antes de emitir.
signal escolhida(tipo: String, tipo_aluguel_id: int)
signal cancelada

## Ícone e recorte (px) = os mesmos usados nas cenas de aeroporto/mapa/comercio/.
const OPCOES := [
	{"tipo": "lanchonete", "nome": "Lanchonete",
		"icone": "res://assets/areas/lanchonete.png", "regiao": Rect2(38, 44, 528, 342)},
	{"tipo": "livraria", "nome": "Livraria",
		"icone": "res://assets/areas/livraria.png", "regiao": Rect2(146, 0, 558, 422)},
	{"tipo": "cafeteria", "nome": "Cafeteria",
		"icone": "res://assets/areas/cafeteria.png", "regiao": Rect2(184, 90, 442, 552)},
	{"tipo": "sushi", "nome": "Sushi",
		"icone": "res://assets/areas/sushi.png", "regiao": Rect2(90, 82, 542, 536)},
	{"tipo": "restaurante", "nome": "Restaurante",
		"icone": "res://assets/areas/restaurante.png", "regiao": Rect2(148, 138, 1128, 1200)},
]

@export var fonte: Font
@export var cor_fundo: Color = Color(0.08, 0.11, 0.2)
@export var cor_borda: Color = Color(0.35, 0.6, 1.0)

var _aberta := false
var _titulo: Label
var _linha: HBoxContainer
var _dica: Label
var _opcoes: Array[Dictionary] = []
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
	_montar_opcoes()
	_aberta = true
	visible = true
	get_tree().paused = true
	for b in _botoes:
		if not b.disabled:
			b.grab_focus()
			break


func fechar() -> void:
	if not _aberta:
		return
	_aberta = false
	visible = false
	get_tree().paused = false


func _escolher(indice: int) -> void:
	if not _aberta or indice < 0 or indice >= _opcoes.size() or _botoes[indice].disabled:
		return
	var op := _opcoes[indice]
	fechar()
	escolhida.emit(str(op.tipo), int(op.id))


func _input(event: InputEvent) -> void:
	if not _aberta or not event is InputEventKey or not event.pressed or event.echo:
		return
	var tecla := int(event.physical_keycode)
	if tecla == KEY_ESCAPE or tecla == KEY_T:
		get_viewport().set_input_as_handled()
		fechar()
		cancelada.emit()
		return
	var escolha := -1
	if tecla >= KEY_1 and tecla <= KEY_9:
		escolha = tecla - KEY_1
	elif tecla >= KEY_KP_1 and tecla <= KEY_KP_9:
		escolha = tecla - KEY_KP_1
	if escolha >= 0 and escolha < _opcoes.size():
		# consome a tecla para a tela de questão (que abre em seguida) não tratá-la como resposta
		get_viewport().set_input_as_handled()
		_escolher(escolha)


# ------------------------------------------------------------------ opções

func _montar_opcoes() -> void:
	_opcoes.clear()
	var conhecidos := {}
	for op in OPCOES:
		conhecidos[op.tipo] = op
	if GameState.tipos_aluguel.is_empty():
		for op in OPCOES:
			_opcoes.append({"tipo": op.tipo, "nome": op.nome, "icone": op.icone, "regiao": op.regiao, "id": -1})
	else:
		for t in GameState.tipos_aluguel:
			var desc := str(t.descricao).strip_edges().to_lower()
			var op: Dictionary = conhecidos.get(desc, {})
			_opcoes.append({
				"tipo": desc,
				"nome": str(op.get("nome", str(t.descricao).capitalize())),
				"icone": str(op.get("icone", "")),
				"regiao": op.get("regiao", Rect2()),
				"id": int(t.id),
				"preco": float(t.preco),
				"renda": float(t.renda),
				"nivel_minimo": int(t.nivel_minimo),
			})

	for c in _linha.get_children():
		c.queue_free()
	_botoes.clear()
	for i in _opcoes.size():
		var b := _criar_cartao(i, _opcoes[i])
		_linha.add_child(b)
		_botoes.append(b)
	_dica.text = "Clique ou use as teclas 1 a %d" % _opcoes.size()


## Motivo pelo qual a opção não pode ser escolhida agora ("" = pode).
func _bloqueio(op: Dictionary) -> String:
	if GameState.aeroporto_id == "" or not op.has("preco"):
		return ""
	if GameState.nivel_atual() < int(op.nivel_minimo):
		return "Requer nível %d" % int(op.nivel_minimo)
	if GameState.dinheiro() < float(op.preco):
		return "Dinheiro insuficiente"
	return ""


func _criar_cartao(i: int, op: Dictionary) -> Button:
	var bloqueio := _bloqueio(op)
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 240)      # largura 0: os cartões dividem o espaço e nunca estouram a tela
	b.clip_contents = true
	b.disabled = bloqueio != ""
	_pintar(b, Color(0.14, 0.19, 0.33), cor_borda.darkened(0.4))
	b.pressed.connect(_escolher.bind(i))

	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	margem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 10)
	b.add_child(margem)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	if b.disabled:
		v.modulate = Color(1, 1, 1, 0.5)
	margem.add_child(v)

	var icone := _icone(op)
	if icone != null:
		var img := TextureRect.new()
		img.texture = icone
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.size_flags_vertical = Control.SIZE_EXPAND_FILL
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(img)
	else:
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", 64)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.size_flags_vertical = Control.SIZE_EXPAND_FILL
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(q)

	v.add_child(_rotulo("%d)  %s" % [i + 1, op.nome], 24, Color.WHITE))
	if op.has("preco"):
		v.add_child(_rotulo("Aluguel %s" % _dinheiro(float(op.preco)), 17, Color(1.0, 0.8, 0.5)))
		var cfg := GameState.renda_da_descricao(str(op.tipo))
		if not cfg.is_empty():
			v.add_child(_rotulo("Renda %s a cada %ds" % [_dinheiro(float(cfg.valor)), int(cfg.intervalo)], 17, Color(0.55, 0.95, 0.6)))
		else:
			v.add_child(_rotulo("Renda %s" % _dinheiro(float(op.renda)), 17, Color(0.55, 0.95, 0.6)))
	if bloqueio != "":
		v.add_child(_rotulo(bloqueio, 17, Color(1, 0.5, 0.5)))
	return b


func _rotulo(texto: String, tamanho: int, cor: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tamanho)
	l.add_theme_color_override("font_color", cor)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 1234.5 -> "1.234,50"
func _dinheiro(v: float) -> String:
	var partes := String.num(absf(v), 2).split(".")
	var inteiro := partes[0]
	var out := ""
	while inteiro.length() > 3:
		out = "." + inteiro.substr(inteiro.length() - 3) + out
		inteiro = inteiro.substr(0, inteiro.length() - 3)
	return inteiro + out + "," + partes[1]


func _icone(op: Dictionary) -> Texture2D:
	var caminho := str(op.get("icone", ""))
	if caminho == "" or not ResourceLoader.exists(caminho):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(caminho)
	atlas.region = op.regiao
	return atlas


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
		margem.add_theme_constant_override("margin_" + lado, 40)
	for lado in ["top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 40)
	raiz.add_child(margem)

	var painel := PanelContainer.new()
	painel.add_theme_stylebox_override("panel", _estilo(cor_fundo, cor_borda, 14, 3))
	margem.add_child(painel)

	var interno := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		interno.add_theme_constant_override("margin_" + lado, 20)
	painel.add_child(interno)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
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

	_linha = HBoxContainer.new()
	_linha.add_theme_constant_override("separation", 12)
	_linha.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_linha)

	var rodape := HBoxContainer.new()
	v.add_child(rodape)
	_dica = Label.new()
	_dica.add_theme_color_override("font_color", Color(0.6, 0.68, 0.85))
	_dica.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rodape.add_child(_dica)
	var cancelar := Button.new()
	cancelar.text = "Cancelar  (Esc)"
	cancelar.custom_minimum_size = Vector2(190, 44)
	cancelar.pressed.connect(func() -> void:
		fechar()
		cancelada.emit())
	rodape.add_child(cancelar)


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
	b.add_theme_stylebox_override("disabled", _estilo(fundo.darkened(0.3), borda.darkened(0.5), 10, 2))
	b.add_theme_stylebox_override("focus", _estilo(Color(0, 0, 0, 0), Color.WHITE, 10, 2))
