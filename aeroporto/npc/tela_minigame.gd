extends CanvasLayer
## Abre qualquer minigame por cima do mapa (jogo pausado) e devolve o controle ao fechar.
##
## Visual: o aeroporto fica ao fundo, borrado, e o minigame roda numa janela de tamanho FIXO
## (TAMANHO_JOGO) no centro da tela. Como cada minigame roda dentro de um SubViewport desse
## tamanho, os três ocupam exatamente o mesmo espaço, e o HUD de cada um (inclusive os
## CanvasLayer internos) fica contido na janela, sem brigar com a tela do host.
##
## Fecha com Esc, com o botão "Fechar" (ou "Voltar", se o minigame tiver o seu), ou quando o
## minigame emite `voltar_pressed` / `fechar_pedido`.
##
## Se o minigame tem um sinal `voltar_pressed`, ele já tem barra e botão próprios: o cabeçalho
## do host (título + "Fechar") é escondido para não ficar nada sobreposto.
## Se o minigame tiver um método `tratar_esc() -> bool`, o Esc é oferecido a ele primeiro
## (retorne true se ele "consumiu" o Esc, por exemplo fechando uma janelinha interna).
##
## Uso:  host.abrir(preload("res://aeroporto/minigames/minesweeper/game.tscn"), "Atendente")
## Sinal `fechado` avisa quando o jogador saiu (dá para ligar recompensa/progresso aqui depois).

signal fechado

## Tamanho (em pixels) da área de jogo, igual para todos os minigames.
const TAMANHO_JOGO := Vector2i(1000, 590)
const ALTURA_CABECALHO := 34
const LARGURA_BORDA := 3
const COR_FUNDO_JOGO := Color("#2b2f3a")
const COR_BORDA := Color(0.35, 0.6, 1.0)

## Desfoque do que está atrás (o mapa). Lê a tela já desenhada pelas camadas de baixo e faz
## uma média de pontos em espiral, então não depende de mipmaps e funciona no GL Compatibility.
## `raio` (em pixels) controla o quanto borra; `tinta` escurece um pouco para destacar a janela.
const SHADER_DESFOQUE := """
shader_type canvas_item;
uniform sampler2D tela : hint_screen_texture, repeat_disable, filter_linear;
uniform float raio = 9.0;
uniform vec4 tinta : source_color = vec4(0.03, 0.05, 0.1, 0.45);

void fragment() {
	vec2 passo = SCREEN_PIXEL_SIZE * raio;
	vec3 soma = vec3(0.0);
	for (int i = 0; i < 48; i++) {
		float fi = float(i);
		float r = sqrt((fi + 0.5) / 48.0);
		float a = fi * 2.39996323;
		soma += texture(tela, SCREEN_UV + vec2(cos(a), sin(a)) * r * passo).rgb;
	}
	vec3 cor = soma / 48.0;
	COLOR = vec4(mix(cor, tinta.rgb, tinta.a), 1.0);
}
"""

var _raiz: Control
var _cabecalho: Control
var _titulo: Label
var _viewport: SubViewport
var _atual: Node
var _aberta := false


func _init() -> void:
	add_to_group("tela_minigame")
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_raiz)

	# 1) aeroporto borrado ao fundo (também engole os cliques que iriam para o mapa)
	_raiz.add_child(_criar_desfoque())

	# 2) janela centralizada: [cabeçalho] + [área de jogo]
	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(centro)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 4)
	centro.add_child(coluna)

	# O cabeçalho sempre ocupa o mesmo espaço (mesmo escondido), assim a janela
	# fica exatamente no mesmo lugar em todos os minigames.
	var largura_total := TAMANHO_JOGO.x + LARGURA_BORDA * 2
	var reserva := Control.new()
	reserva.custom_minimum_size = Vector2(largura_total, ALTURA_CABECALHO)
	reserva.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coluna.add_child(reserva)

	_cabecalho = HBoxContainer.new()
	_cabecalho.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reserva.add_child(_cabecalho)

	_titulo = Label.new()
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_titulo.add_theme_font_size_override("font_size", 20)
	_titulo.add_theme_color_override("font_color", Color.WHITE)
	_titulo.add_theme_color_override("font_outline_color", Color.BLACK)
	_titulo.add_theme_constant_override("outline_size", 6)
	_cabecalho.add_child(_titulo)

	var botao := Button.new()
	botao.text = "Fechar  (Esc)"
	botao.focus_mode = Control.FOCUS_NONE
	botao.pressed.connect(fechar)
	_cabecalho.add_child(botao)

	# 3) a área de jogo em si: moldura + SubViewport de tamanho fixo
	var painel := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COR_FUNDO_JOGO
	estilo.border_color = COR_BORDA
	estilo.set_border_width_all(LARGURA_BORDA)
	estilo.set_content_margin_all(LARGURA_BORDA)
	painel.add_theme_stylebox_override("panel", estilo)
	coluna.add_child(painel)

	var contentor := SubViewportContainer.new()
	contentor.custom_minimum_size = Vector2(TAMANHO_JOGO)
	contentor.stretch = false
	painel.add_child(contentor)

	_viewport = SubViewport.new()
	_viewport.size = TAMANHO_JOGO
	_viewport.transparent_bg = false
	contentor.add_child(_viewport)

	# fundo da área de jogo (os minigames que não têm fundo próprio usam este)
	var fundo := ColorRect.new()
	fundo.color = COR_FUNDO_JOGO
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(fundo)


func _criar_desfoque() -> ColorRect:
	var shader := Shader.new()
	shader.code = SHADER_DESFOQUE
	var material := ShaderMaterial.new()
	material.shader = shader
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.material = material
	return r


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
	_viewport.add_child(_atual)

	# minigame com barra própria (botão "Voltar"): esconde o cabeçalho do host
	_cabecalho.visible = not _atual.has_signal("voltar_pressed")
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
		# o minigame pode usar o Esc antes (ex.: fechar a janela de recordes)
		var consumido := false
		if is_instance_valid(_atual) and _atual.has_method("tratar_esc"):
			consumido = bool(_atual.call("tratar_esc"))
		if not consumido:
			fechar()
		get_viewport().set_input_as_handled()
