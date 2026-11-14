extends Node
## Tela de questão matemática, montada 100% por código (sem precisar de .tscn).
## Estende Node de propósito: o script pode ser anexado a QUALQUER nó
## (CanvasLayer, Control, Node...) ou instanciado por código dentro de um CanvasLayer.
## Uso:  var quiz := preload("res://ui/quiz_screen.gd").new()
##       add_child(quiz)            # exige GameState.carregar() já concluído
##       quiz.fechada.connect(...)  # emitido ao tocar em "Fechar"

signal fechada

const COR_ACERTO := Color(0.55, 1.0, 0.55)
const COR_ERRO := Color(1.0, 0.55, 0.55)

var _questao: Dictionary = {}
var _ocupado := false

var _cabecalho: Label
var _enunciado: Label
var _botoes: Array[Button] = []
var _feedback: Label
var _btn_proxima: Button
var _btn_evoluir: Button
var _btn_fechar: Button


func _ready() -> void:
	_montar_ui()
	GameState.dinheiro_mudou.connect(func(_v): _atualizar_cabecalho())
	_proxima_questao()


# ------------------------- UI -------------------------
func _montar_ui() -> void:
	# Raiz Control interna: ocupa a área do pai (viewport quando o pai é CanvasLayer).
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 24)
	raiz.add_child(margem)

	var caixa := VBoxContainer.new()
	caixa.add_theme_constant_override("separation", 12)
	margem.add_child(caixa)

	_cabecalho = Label.new()
	caixa.add_child(_cabecalho)

	_enunciado = Label.new()
	_enunciado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enunciado.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enunciado.custom_minimum_size = Vector2(0, 120)
	caixa.add_child(_enunciado)

	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if "autowrap_mode" in b:   # Godot >= 4.2
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_ao_escolher.bind(i))
		caixa.add_child(b)
		_botoes.append(b)

	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caixa.add_child(_feedback)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 12)
	caixa.add_child(linha)

	_btn_proxima = Button.new()
	_btn_proxima.text = "Próxima questão"
	_btn_proxima.pressed.connect(_proxima_questao)
	linha.add_child(_btn_proxima)

	_btn_evoluir = Button.new()
	_btn_evoluir.text = "Evoluir aeroporto"
	_btn_evoluir.pressed.connect(_ao_evoluir)
	linha.add_child(_btn_evoluir)

	_btn_fechar = Button.new()
	_btn_fechar.text = "Fechar"
	_btn_fechar.pressed.connect(func(): fechada.emit())
	linha.add_child(_btn_fechar)


func _atualizar_cabecalho() -> void:
	var p := GameState.progresso_nivel()
	_cabecalho.text = "Nível %d  ·  Acertos %d/%d  ·  Dinheiro R$ %s" % [
		GameState.nivel_atual(), p.x, p.y, _fmt(GameState.dinheiro())]


# ------------------------- Fluxo -------------------------
func _proxima_questao() -> void:
	_atualizar_cabecalho()
	_feedback.text = ""
	_btn_proxima.visible = false
	_btn_evoluir.visible = false
	_questao = GameState.sortear_questao()   # local, sem rede

	if _questao.is_empty():
		_mostrar_fim_de_nivel()
		return

	_enunciado.text = _questao.enunciado
	for i in _botoes.size():
		var b := _botoes[i]
		var alt: Dictionary = _questao.alternativas[i]
		b.text = "%s)  %s" % [char(97 + i), alt.enunciado]
		b.modulate = Color.WHITE
		b.disabled = false
		b.visible = true


func _ao_escolher(indice: int) -> void:
	if _ocupado or _questao.is_empty():
		return
	_ocupado = true
	_set_botoes_habilitados(false)
	_feedback.text = "Verificando..."

	var alt: Dictionary = _questao.alternativas[indice]
	var r := await GameState.responder(_questao.id, alt.id)   # validação no servidor
	_ocupado = false

	if not r.ok:
		# Falha de rede/validação: nada foi alterado no cache; deixa tentar de novo.
		_feedback.text = "Não foi possível enviar a resposta: " + r.error
		_set_botoes_habilitados(true)
		return

	var d: Dictionary = r.data
	if d.get("acertou", false):
		_botoes[indice].modulate = COR_ACERTO
		var txt := "Correto!"
		if float(d.get("recompensa", 0)) > 0:
			txt += "  +R$ %s" % _fmt(float(d.recompensa))
		else:
			txt += "  (sem recompensa: já havia errado esta questão)"
		if d.get("explicacao") != null:
			txt += "\n" + str(d.explicacao)
		_feedback.text = txt
		_set_botoes_habilitados(false)
		_btn_proxima.visible = true
		_btn_evoluir.visible = GameState.pode_evoluir()
	else:
		_botoes[indice].modulate = COR_ERRO
		_botoes[indice].disabled = true          # esta alternativa fica descartada
		_feedback.text = "Resposta incorreta. Tente outra alternativa (sem recompensa)."
		for i in _botoes.size():                 # reabilita as que sobraram
			if i != indice and _botoes[i].modulate != COR_ERRO:
				_botoes[i].disabled = false
	_atualizar_cabecalho()


func _mostrar_fim_de_nivel() -> void:
	_enunciado.text = "Você concluiu todas as questões deste nível!"
	for b in _botoes:
		b.visible = false
	if GameState.pode_evoluir():
		_feedback.text = "Você já pode evoluir seu aeroporto."
		_btn_evoluir.visible = true
	elif GameState.niveis.has(GameState.nivel_atual() + 1):
		var prox: Dictionary = GameState.niveis[GameState.nivel_atual() + 1]
		_feedback.text = "Para evoluir é preciso R$ %s e %d acertos." % [
			_fmt(float(prox.dinheiro_necessario)), int(prox.questoes_necessarias)]
	else:
		_feedback.text = "Nível máximo atingido. Parabéns!"


func _ao_evoluir() -> void:
	if _ocupado:
		return
	_ocupado = true
	_btn_evoluir.disabled = true
	var r := await GameState.evoluir()
	_ocupado = false
	_btn_evoluir.disabled = false
	if r.ok:
		_proxima_questao()
	else:
		_feedback.text = "Não foi possível evoluir: " + r.error


func _set_botoes_habilitados(v: bool) -> void:
	for b in _botoes:
		b.disabled = not v


## 1234567.5 -> "1.234.567,50"
static func _fmt(v: float) -> String:
	var s := "%.2f" % v
	var partes := s.split(".")
	var inteiro := partes[0]
	var out := ""
	while inteiro.length() > 3:
		out = "." + inteiro.substr(inteiro.length() - 3) + out
		inteiro = inteiro.substr(0, inteiro.length() - 3)
	return inteiro + out + "," + partes[1]
