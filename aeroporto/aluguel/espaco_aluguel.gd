extends Sprite2D
## Espaço do aeroporto que pode ser alugado (o sprite do "+").
## Quando o jogador chega perto aparece "T - Alugar espaço". Apertar T ou clicar com o mouse
## abre a escolha do tipo (preço/nível vêm do banco) e, em seguida, a tela de questão.
## Acertou -> o aluguel é feito no servidor (GameState.alugar) e a loja aparece no lugar do "+".
##
## Cada espaço tem um `numero_area` (1 a 27) = coluna numero_area de aluguel_localizacao.
## Se ficar 0, o número é lido do nome do nó (AreaAluguel7 -> 7).
## O sinal `area_alugada` avisa o fim do fluxo.

const BancoQuestoes := preload("res://aeroporto/questoes/banco_questoes.gd")
const TelaQuestao := preload("res://aeroporto/questoes/tela_questao.tscn")
const TelaEscolha := preload("res://aeroporto/aluguel/tela_escolha_area.gd")
## Cena do estabelecimento que aparece depois de alugado (chave = descricao do tipo_aluguel em minúsculas).
const LOJAS := {
	"lanchonete": preload("res://aeroporto/mapa/comercio/lanchonete.tscn"),
	"livraria": preload("res://aeroporto/mapa/comercio/livraria.tscn"),
	"cafeteria": preload("res://aeroporto/mapa/comercio/cafeteria.tscn"),
	"sushi": preload("res://aeroporto/mapa/comercio/sushi.tscn"),
	"restaurante": preload("res://aeroporto/mapa/comercio/restaurante.tscn"),
}

## Emitido quando o fluxo termina (escolheu o tipo, respondeu e, se acertou, tentou alugar).
## `acertou` é true/false, ou null se a questão não foi respondida (sem questões / fechada).
signal area_alugada(tipo: String, acertou: Variant)

## Folga (px) ao redor do sprite em que o jogador é considerado "perto".
@export var folga_lateral: float = 160.0
@export var folga_cima: float = 120.0
## O jogador anda na frente (abaixo) do espaço, então a zona se estende mais para baixo.
@export var folga_baixo: float = 380.0
## Folga (px) ao redor do sprite em que o clique do mouse vale.
@export var folga_clique: float = 40.0
@export var contexto: String = "aluguel"
## Número da área (1 a 27) gravado no banco. 0 = descobrir pelo nome do nó (AreaAluguelN).
@export var numero_area: int = 0

var _perto := false
var _dica: Label
var _zona: Area2D
var _jogador: Node2D
var _alugada := false
var _ocupado := false
var _loja: Node2D


func _ready() -> void:
	_registrar_input()
	add_to_group("espacos_aluguel")
	if numero_area <= 0:
		numero_area = _numero_do_nome()
	if numero_area <= 0:
		push_warning("[Aluguel] %s sem numero_area (use o nome AreaAluguelN ou defina no Inspector)." % name)
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
	_dica.text = ("Área %d  •  " % numero_area if numero_area > 0 else "") + "T / clique - Alugar"
	_dica.add_theme_font_size_override("font_size", 16)
	_dica.add_theme_color_override("font_outline_color", Color.BLACK)
	_dica.add_theme_constant_override("outline_size", 6)
	_dica.z_index = 20
	_dica.visible = false
	add_child(_dica)
	# o Label herdaria a escala do sprite; compensa e posiciona acima dele
	_dica.scale = Vector2(1.0 / scale.x, 1.0 / scale.y)
	_dica.position = Vector2(-90.0 / scale.x, -(tam.y * 0.5 + 40.0) / scale.y)

	GameState.aluguel_feito.connect(_ao_aluguel_feito)
	_sincronizar()


func _unhandled_input(event: InputEvent) -> void:
	if not _perto or get_tree().paused or _alugada or _ocupado:
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
	if _alugada or _ocupado:
		return
	if GameState.aeroporto_id == "":
		_aviso("Nenhum save carregado.", Color(1, 0.6, 0.5))
		return
	if numero_area <= 0:
		_aviso("Esta área não tem número definido.", Color(1, 0.6, 0.5))
		return
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


func _ao_escolher(tipo: String, tipo_aluguel_id: int) -> void:
	var escolha := get_tree().get_first_node_in_group("tela_escolha_area")
	if escolha != null and escolha.cancelada.is_connected(_ao_cancelar):
		escolha.cancelada.disconnect(_ao_cancelar)
	call_deferred("_abrir_questao", tipo, tipo_aluguel_id)


func _abrir_questao(tipo: String, tipo_aluguel_id: int) -> void:
	var tela := get_tree().get_first_node_in_group("tela_questao")
	if tela == null:
		tela = TelaQuestao.instantiate()
		get_tree().root.add_child(tela)
	_ocupado = true
	var resultado := {"acertou": null}
	tela.resposta_escolhida.connect(
		func(_q: Dictionary, _i: int, acertou: Variant) -> void: resultado.acertou = acertou,
		CONNECT_ONE_SHOT)
	# O aluguel só é tentado quando o jogador fecha a tela (depois de ver o resultado da questão).
	tela.fechada.connect(
		func(_respondida: bool) -> void: _concluir(tipo, tipo_aluguel_id, resultado.acertou),
		CONNECT_ONE_SHOT)
	tela.abrir(BancoQuestoes.proxima_questao(contexto + "_" + tipo), "Alugar espaço  •  %s" % tipo.capitalize())


func _concluir(tipo: String, tipo_aluguel_id: int, acertou: Variant) -> void:
	if acertou == true:
		if tipo_aluguel_id < 0:
			_aviso("Tipos de aluguel indisponíveis (sem dados do banco).", Color(1, 0.6, 0.5))
		else:
			var r: Dictionary = await GameState.alugar(tipo_aluguel_id, numero_area)
			if r.ok:
				_aviso("%s alugada!" % tipo.capitalize(), Color(0.55, 1, 0.6))
			else:
				_aviso("Não foi possível alugar: %s" % r.error, Color(1, 0.6, 0.5))
	elif acertou == false:
		_aviso("Resposta errada: o espaço não foi alugado.", Color(1, 0.6, 0.5))
	_ocupado = false
	area_alugada.emit(tipo, acertou)


## Mostra a loja (e esconde o "+") se esta área já está alugada no save.
func _sincronizar() -> void:
	var linha := GameState.aluguel_da_area(numero_area) if numero_area > 0 else {}
	_alugada = not linha.is_empty()
	if _alugada:
		_dica.visible = false
		var tipo := str(GameState.tipo_aluguel(int(linha.get("tipo_aluguel_id", -1))).get("descricao", "")).strip_edges().to_lower()
		if LOJAS.has(tipo):
			self_modulate = Color(1, 1, 1, 0)        # esconde o "+", mantém a zona e o rótulo
			if _loja == null:
				_loja = LOJAS[tipo].instantiate()
				_loja.z_index = 100
				get_parent().add_child(_loja)
				_loja.global_position = global_position
		else:
			self_modulate = Color(1, 1, 1, 0.35)     # tipo sem cena: só "apaga" o "+"
	else:
		self_modulate = Color.WHITE


func _ao_aluguel_feito(numero: int) -> void:
	if numero == numero_area:
		_sincronizar()


func _numero_do_nome() -> int:
	var nome := String(name)
	var digitos := ""
	for i in range(nome.length() - 1, -1, -1):
		var c := nome[i]
		if c < "0" or c > "9":
			break
		digitos = c + digitos
	return int(digitos) if digitos != "" else 0


## Mensagem flutuante acima do espaço (some sozinha).
func _aviso(texto: String, cor: Color) -> void:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", cor)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.z_index = 40
	add_child(l)
	l.scale = Vector2(1.0 / scale.x, 1.0 / scale.y)
	l.position = _dica.position + Vector2(0, -40.0 / scale.y)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _tamanho() -> Vector2:
	var base := texture.get_size() if texture != null else Vector2(128, 128)
	return base * scale.abs()


func _ao_entrar(corpo: Node2D) -> void:
	_jogador = corpo
	_perto = true
	_dica.visible = not _alugada


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
