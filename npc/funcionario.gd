extends StaticBody2D
## Funcionário do aeroporto: fica parado no posto (atrás de um balcão) e, quando o jogador
## chega perto, aparece "E - Falar". Ao apertar E abre a tela de questão matemática.
##
## Dica: arraste/duplique a cena `funcionario.tscn` para o mapa e ajuste as propriedades
## no Inspector (nome, cargo, contexto, direção, cor).

const Sprites := preload("res://npc/personagem_sprites.gd")
const BancoQuestoes := preload("res://questoes/banco_questoes.gd")
const TelaQuestao := preload("res://questoes/tela_questao.tscn")
const TEXTURA_PADRAO := "res://assets/npc/personagem.png"

@export var nome_funcionario: String = "Funcionário"
@export var cargo: String = ""
## Identificador usado para pedir a questão ao banco (ex.: "checkin", "info", "pesagem").
@export var contexto: String = ""
@export_enum("baixo", "esquerda", "cima", "direita") var direcao: String = "baixo"
## Se vazio, usa assets/npc/personagem.png.
@export var textura: Texture2D
## Variação de cor das roupas (0 a 1). -1 = sem alteração.
@export_range(-1.0, 1.0) var matiz: float = -1.0
@export var olhar_para_jogador: bool = true
@export var linha_cabeca: int = 19

@onready var corpo: AnimatedSprite2D = $Corpo
@onready var cabeca: AnimatedSprite2D = $Cabeca
@onready var zona: Area2D = $Zona

var _perto := false
var _dica: Label
var _jogador: Node2D
var _dir_atual := ""


func _ready() -> void:
	_registrar_input()
	var tex: Texture2D = textura if textura != null else load(TEXTURA_PADRAO)
	var frames := Sprites.montar(tex, linha_cabeca)
	corpo.sprite_frames = frames["corpo"]
	cabeca.sprite_frames = frames["cabeca"]
	Sprites.posicionar(corpo, cabeca, linha_cabeca)
	if matiz >= 0.0:
		var mat := Sprites.material_cor(matiz, 1.0)
		corpo.material = mat
		cabeca.material = mat
	_olhar(direcao)

	_dica = Label.new()
	_dica.text = "E - Falar"
	_dica.add_theme_font_size_override("font_size", 16)
	_dica.add_theme_color_override("font_outline_color", Color.BLACK)
	_dica.add_theme_constant_override("outline_size", 6)
	_dica.position = Vector2(-34, -92)
	_dica.z_index = 20
	_dica.visible = false
	add_child(_dica)

	zona.body_entered.connect(_ao_entrar)
	zona.body_exited.connect(_ao_sair)


func _process(_delta: float) -> void:
	if _perto and olhar_para_jogador and is_instance_valid(_jogador):
		var v := _jogador.global_position - global_position
		_olhar("direita" if v.x > 0.0 else "esquerda" if absf(v.x) > absf(v.y) else "baixo" if v.y > 0.0 else "cima")


func _unhandled_input(event: InputEvent) -> void:
	if _perto and event.is_action_pressed("interagir") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		_interagir()


func _interagir() -> void:
	var tela := get_tree().get_first_node_in_group("tela_questao")
	if tela == null:
		tela = TelaQuestao.instantiate()
		get_tree().root.add_child(tela)
	var titulo := nome_funcionario if cargo == "" else "%s  •  %s" % [nome_funcionario, cargo]
	#tela.abrir(BancoQuestoes.proxima_questao(contexto), titulo)


func _ao_entrar(corpo_entrou: Node2D) -> void:
	_perto = true
	_jogador = corpo_entrou
	_dica.visible = true


func _ao_sair(_corpo_saiu: Node2D) -> void:
	_perto = false
	_dica.visible = false
	_olhar(direcao)


func _olhar(dir: String) -> void:
	if dir == _dir_atual:
		return
	_dir_atual = dir
	Sprites.tocar(corpo, cabeca, "parado_" + dir)


func _registrar_input() -> void:
	if InputMap.has_action("interagir"):
		return
	InputMap.add_action("interagir")
	for tecla in [KEY_E, KEY_ENTER]:
		var ev := InputEventKey.new()
		ev.physical_keycode = tecla
		InputMap.action_add_event("interagir", ev)
