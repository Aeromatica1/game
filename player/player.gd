extends CharacterBody2D
## Personagem top-down: anda com WASD/setas e corre segurando ESPAÇO.
## O spritesheet (6 colunas x 4 linhas, células de 28x28) é fatiado por código.
##   Linhas:  0 = baixo, 1 = esquerda, 2 = cima, 3 = direita
##   Colunas: 0-2 = andar (parado, passo A, passo B) | 3-5 = correr (parado, passo A, passo B)

@export var velocidade_andar: float = 300.0
@export var velocidade_correr: float = 600.0
@export var aceleracao: float = 1200.0
@export var atrito: float = 1600.0
@export var camera_zoom: Vector2 = Vector2(1, 1)
## Linha (em px do sprite de 28) onde a cabeça termina. A cabeça é desenhada num z_index maior,
## então ela nunca fica escondida atrás do corpo de outro personagem.
@export var linha_cabeca: int = 19

const Sprites := preload("res://npc/personagem_sprites.gd")
const FPS_ANDAR := 8.0
const FPS_CORRER := 12.0

var direcao_olhando: String = "baixo"
var correndo: bool = false

@onready var corpo: AnimatedSprite2D = $AnimatedSprite2D
@onready var cabeca: AnimatedSprite2D = $Cabeca
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	_registrar_inputs()
	_montar_animacoes()
	camera.zoom = camera_zoom
	camera.make_current() # a Camera2D do mapa fica parada; esta segue o jogador
	_atualizar_animacao(false)


func _physics_process(delta: float) -> void:
	var entrada := Input.get_vector("mover_esquerda", "mover_direita", "mover_cima", "mover_baixo")
	correndo = Input.is_action_pressed("correr") and entrada != Vector2.ZERO

	if entrada != Vector2.ZERO:
		_atualizar_direcao(entrada)
		var alvo := entrada * (velocidade_correr if correndo else velocidade_andar)
		velocity = velocity.move_toward(alvo, aceleracao * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, atrito * delta)

	move_and_slide()
	_atualizar_animacao(velocity.length() > 5.0)


func _atualizar_direcao(entrada: Vector2) -> void:
	# Em diagonal, mantém a direção atual se ela ainda faz parte do movimento
	# (evita o sprite ficar "tremendo" entre esquerda/cima, por exemplo).
	var horizontal := "direita" if entrada.x > 0.0 else "esquerda"
	var vertical := "baixo" if entrada.y > 0.0 else "cima"
	if entrada.x == 0.0:
		direcao_olhando = vertical
	elif entrada.y == 0.0:
		direcao_olhando = horizontal
	elif direcao_olhando != horizontal and direcao_olhando != vertical:
		direcao_olhando = horizontal if absf(entrada.x) >= absf(entrada.y) else vertical


func _atualizar_animacao(movendo: bool) -> void:
	var nome := "parado_" + direcao_olhando
	if movendo:
		nome = ("correr_" if correndo else "andar_") + direcao_olhando
	if corpo.animation != nome:
		# ao trocar entre andar/correr, mantém o frame para o ciclo não reiniciar
		var mesmo_tipo := nome.get_slice("_", 0) != "parado" and corpo.animation.get_slice("_", 0) != "parado"
		var frame_atual := corpo.frame
		corpo.play(nome)
		cabeca.play(nome)
		if mesmo_tipo:
			corpo.set_frame_and_progress(frame_atual, 0.0)
		cabeca.set_frame_and_progress(corpo.frame, corpo.frame_progress)
	elif not corpo.is_playing():
		corpo.play(nome)
		cabeca.play(nome)


func _montar_animacoes() -> void:
	var textura: Texture2D = preload("res://assets/player/personagem.png")
	var frames := Sprites.montar(textura, linha_cabeca, true, FPS_ANDAR, FPS_CORRER)
	corpo.sprite_frames = frames["corpo"]
	cabeca.sprite_frames = frames["cabeca"]
	Sprites.posicionar(corpo, cabeca, linha_cabeca)
	corpo.play("parado_baixo")
	cabeca.play("parado_baixo")


## Cria as ações de input por código, então não é preciso mexer no Project Settings.
func _registrar_inputs() -> void:
	_acao("mover_esquerda", [KEY_A, KEY_LEFT])
	_acao("mover_direita", [KEY_D, KEY_RIGHT])
	_acao("mover_cima", [KEY_W, KEY_UP])
	_acao("mover_baixo", [KEY_S, KEY_DOWN])
	_acao("correr", [KEY_SHIFT])


func _acao(nome: StringName, teclas: Array) -> void:
	if InputMap.has_action(nome):
		return
	InputMap.add_action(nome)
	for tecla in teclas:
		var ev := InputEventKey.new()
		ev.physical_keycode = tecla
		InputMap.action_add_event(nome, ev)
