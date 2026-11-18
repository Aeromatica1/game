extends CanvasLayer
## Autoload "Transicao": fader (fade para preto e volta) entre telas e entre cenas.
##
## Uso:
##   Transicao.executar(func() -> void: ...troca de tela/cena aqui...)
##
## Escurece a tela, roda a ação com tudo coberto e clareia de novo. Durante a transição a
## cobertura bloqueia o mouse; se vier outro pedido enquanto uma transição roda, ele é ignorado
## (evita duplo clique em "Voltar" pular duas telas).
## Roda com o jogo pausado (game over, menus por cima do mapa).

const DURACAO := 0.25           # s, para escurecer e para clarear
const DURACAO_ABERTURA := 0.5   # s, clareada inicial ao abrir o jogo

var _cobertura: ColorRect
var _tween: Tween
var _ocupado := false


func _ready() -> void:
	layer = 128                                  # acima de qualquer menu (os do mapa vão até ~120)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_cobertura = ColorRect.new()
	_cobertura.name = "Cobertura"
	_cobertura.color = Color.BLACK
	_cobertura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cobertura)
	_cobertura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Abertura do jogo: começa no preto e clareia.
	_cobertura.modulate.a = 1.0
	await get_tree().process_frame
	_animar(0.0, DURACAO_ABERTURA)


## Escurece, roda `acao` (pode ser corrotina) e clareia. Ignorado se já houver transição.
func executar(acao: Callable) -> void:
	if _ocupado:
		return
	_ocupado = true
	_cobertura.mouse_filter = Control.MOUSE_FILTER_STOP
	await _animar(1.0, DURACAO)
	await acao.call()
	# Troca de cena é adiada para o fim do frame: espera a cena nova existir e desenhar.
	await get_tree().process_frame
	await get_tree().process_frame
	await _animar(0.0, DURACAO)
	_cobertura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ocupado = false


func _animar(alvo: float, duracao: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_cobertura, "modulate:a", alvo, duracao)
	await _tween.finished
