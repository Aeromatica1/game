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

const TAMANHO_CELULA := Vector2i(28, 28)
const DIRECOES := ["baixo", "esquerda", "cima", "direita"]
const FPS_ANDAR := 8.0
const FPS_CORRER := 12.0

var direcao_olhando: String = "baixo"
var correndo: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
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
	if sprite.animation != nome:
		# ao trocar entre andar/correr, mantém o frame para o ciclo não reiniciar
		var mesmo_tipo := nome.get_slice("_", 0) != "parado" and sprite.animation.get_slice("_", 0) != "parado"
		var frame_atual := sprite.frame
		sprite.play(nome)
		if mesmo_tipo:
			sprite.set_frame_and_progress(frame_atual, 0.0)
	elif not sprite.is_playing():
		sprite.play(nome)


func _montar_animacoes() -> void:
	var textura: Texture2D = preload("res://assets/player/personagem.png")
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for linha in DIRECOES.size():
		var dir: String = DIRECOES[linha]

		# parado (um único frame)
		frames.add_animation("parado_" + dir)
		frames.set_animation_loop("parado_" + dir, false)
		frames.add_frame("parado_" + dir, _frame(textura, 0, linha))

		# andar: parado, passo A, parado, passo B
		frames.add_animation("andar_" + dir)
		frames.set_animation_speed("andar_" + dir, FPS_ANDAR)
		for coluna in [1, 0, 2, 0]:
			frames.add_frame("andar_" + dir, _frame(textura, coluna, linha))

		# correr: mesmo ciclo usando as colunas 3-5
		frames.add_animation("correr_" + dir)
		frames.set_animation_speed("correr_" + dir, FPS_CORRER)
		for coluna in [4, 3, 5, 3]:
			frames.add_frame("correr_" + dir, _frame(textura, coluna, linha))

	sprite.sprite_frames = frames
	sprite.play("parado_baixo")


func _frame(textura: Texture2D, coluna: int, linha: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = textura
	atlas.region = Rect2(Vector2(coluna, linha) * Vector2(TAMANHO_CELULA), Vector2(TAMANHO_CELULA))
	return atlas


## Cria as ações de input por código, então não é preciso mexer no Project Settings.
func _registrar_inputs() -> void:
	_acao("mover_esquerda", [KEY_A, KEY_LEFT])
	_acao("mover_direita", [KEY_D, KEY_RIGHT])
	_acao("mover_cima", [KEY_W, KEY_UP])
	_acao("mover_baixo", [KEY_S, KEY_DOWN])
	_acao("correr", [KEY_SPACE])


func _acao(nome: StringName, teclas: Array) -> void:
	if InputMap.has_action(nome):
		return
	InputMap.add_action(nome)
	for tecla in teclas:
		var ev := InputEventKey.new()
		ev.physical_keycode = tecla
		InputMap.action_add_event(nome, ev)
