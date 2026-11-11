extends Sprite2D
## Espaço do aeroporto que pode ser alugado (o sprite do "+").
## Quando o jogador chega perto aparece "T - Alugar espaço". Apertar T ou clicar com o mouse
## abre a escolha do tipo (lanchonete/livraria/cafeteria/loja) e, em seguida, a tela de questão
## de matemática (por enquanto só o espaço em branco, igual ao do funcionário).
##
## Para ligar este script a um espaço novo: use um Sprite2D com este script.
## O sinal `area_alugada` avisa o tipo escolhido depois que o jogador responde.

const BancoQuestoes := preload("res://questoes/banco_questoes.gd")
const TelaQuestao := preload("res://questoes/tela_questao.tscn")
const TelaEscolha := preload("res://aluguel/tela_escolha_area.gd")

## Emitido quando o jogador termina o fluxo (escolheu a área e respondeu a questão).
## `acertou` é true/false se a questão tem gabarito, ou null (sem gabarito / placeholder).
signal area_alugada(tipo: String, acertou: Variant)

## Folga (px) ao redor do sprite em que o jogador é considerado "perto".
@export var folga_lateral: float = 160.0
@export var folga_cima: float = 120.0
## O jogador anda na frente (abaixo) do espaço, então a zona se estende mais para baixo.
@export var folga_baixo: float = 380.0
## Folga (px) ao redor do sprite em que o clique do mouse vale.
@export var folga_clique: float = 40.0
@export var contexto: String = "aluguel"

var _perto := false
var _dica: Label
var _zona: Area2D
var _jogador: Node2D


func _ready() -> void:
	_registrar_input()
	add_to_group("espacos_aluguel")
	var tam := _tamanho()

	_zona = Area2D.new()
	_zona.collision_layer = 0
	_zona.collision_mask = 2 # jogador
	var forma := CollisionShape2D.new()
	var ret := RectangleShape2D.new()
	ret.size = Vector2(tam.x + folga_lateral * 2.0, tam.y + folga_cima + folga_baixo)
	forma.shape = ret
	forma.position = Vector2(0, (folga_baixo - folga_cima) * 0.5)
	_zona.add_child(forma)
	add_child(_zona)
	_zona.body_entered.connect(_ao_entrar)
	_zona.body_exited.connect(_ao_sair)

	_dica = Label.new()
	_dica.text = "T / clique - Alugar espaço"
	_dica.add_theme_font_size_override("font_size", 16)
	_dica.add_theme_color_override("font_outline_color", Color.BLACK)
	_dica.add_theme_constant_override("outline_size", 6)
	_dica.z_index = 20
	_dica.visible = false
	add_child(_dica)
	# o Label herdaria a escala do sprite; compensa e posiciona acima dele
	_dica.scale = Vector2(1.0 / scale.x, 1.0 / scale.y)
	_dica.position = Vector2(-90.0 / scale.x, -(tam.y * 0.5 + 40.0) / scale.y)


func _unhandled_input(event: InputEvent) -> void:
	if not _perto or get_tree().paused:
		return
	if event.is_action_pressed("alugar_espaco"):
		if not _e_o_mais_proximo():
			return
		get_viewport().set_input_as_handled()
		_iniciar()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tam := _tamanho() + Vector2.ONE * folga_clique * 2.0
		var ret := Rect2(global_position - tam * 0.5, tam)
		if ret.has_point(get_global_mouse_position()):
			get_viewport().set_input_as_handled()
			_iniciar()


## Com zonas que se sobrepõem, a tecla T vale só para o espaço mais próximo do jogador.
func _e_o_mais_proximo() -> bool:
	var meu := absf(global_position.x - _jogador_x())
	for outro in get_tree().get_nodes_in_group("espacos_aluguel"):
		if outro != self and outro._perto and absf(outro.global_position.x - _jogador_x()) < meu:
			return false
	return true


func _jogador_x() -> float:
	return _jogador.global_position.x if is_instance_valid(_jogador) else global_position.x


func _iniciar() -> void:
	var escolha := get_tree().get_first_node_in_group("tela_escolha_area")
	if escolha == null:
		escolha = TelaEscolha.new()
		get_tree().root.add_child(escolha)
	# conecta uma vez por abertura (evita duplicar se o jogador cancelar e abrir de novo)
	if not escolha.escolhida.is_connected(_ao_escolher):
		escolha.escolhida.connect(_ao_escolher, CONNECT_ONE_SHOT)
	if not escolha.cancelada.is_connected(_ao_cancelar):
		escolha.cancelada.connect(_ao_cancelar, CONNECT_ONE_SHOT)
	escolha.abrir("Alugar espaço")


func _ao_cancelar() -> void:
	var escolha := get_tree().get_first_node_in_group("tela_escolha_area")
	if escolha != null and escolha.escolhida.is_connected(_ao_escolher):
		escolha.escolhida.disconnect(_ao_escolher)


func _ao_escolher(tipo: String) -> void:
	var escolha := get_tree().get_first_node_in_group("tela_escolha_area")
	if escolha != null and escolha.cancelada.is_connected(_ao_cancelar):
		escolha.cancelada.disconnect(_ao_cancelar)
	call_deferred("_abrir_questao", tipo)


func _abrir_questao(tipo: String) -> void:
	var tela := get_tree().get_first_node_in_group("tela_questao")
	if tela == null:
		tela = TelaQuestao.instantiate()
		get_tree().root.add_child(tela)
	tela.resposta_escolhida.connect(
		func(_q: Dictionary, _i: int, acertou: Variant) -> void: area_alugada.emit(tipo, acertou),
		CONNECT_ONE_SHOT)
	tela.abrir(BancoQuestoes.proxima_questao(contexto + "_" + tipo), "Alugar espaço  •  %s" % tipo.capitalize())


func _tamanho() -> Vector2:
	var base := texture.get_size() if texture != null else Vector2(128, 128)
	return base * scale.abs()


func _ao_entrar(corpo: Node2D) -> void:
	_jogador = corpo
	_perto = true
	_dica.visible = true


func _ao_sair(_corpo: Node2D) -> void:
	_perto = false
	_dica.visible = false


func _registrar_input() -> void:
	if InputMap.has_action("alugar_espaco"):
		return
	InputMap.add_action("alugar_espaco")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	InputMap.action_add_event("alugar_espaco", ev)
