extends CharacterBody2D
## Passageiro (NPC). Anda de célula em célula como nos jogos Pokémon, para um pouco,
## olha em volta, e às vezes senta numa poltrona/banco por um tempo.
## Quem cria e controla a quantidade de NPCs é o `passageiros_manager.gd`.
##
## O spritesheet tem o mesmo layout do jogador (6 colunas x 4 linhas, células 28x28):
##   Linhas:  0 = baixo, 1 = esquerda, 2 = cima, 3 = direita
##   Colunas: 0-2 = andar (parado, passo A, passo B)

enum Estado { PARADO, ESPERANDO, ANDANDO, SENTANDO, SENTADO, LEVANTANDO }

const Sprites := preload("res://npc/personagem_sprites.gd")
const DIRECOES := ["baixo", "esquerda", "cima", "direita"]
const TEXTURA_PADRAO := "res://assets/npc/personagem.png"

var m: Node2D                      # PassageirosManager
var estado: Estado = Estado.PARADO
var cel: Vector2i                  # célula atual (quando não está sentado)
var assento = null                 # PassageirosManager.Assento reservado (ou null)
var velocidade: float = 90.0
var direcao: String = "baixo"
var removendo: bool = false

var _caminho: Array[Vector2i] = []
var _idx: int = 0
var _alvo: Vector2
var _timer: float = 0.0
var _tentativas: int = 0
var _tween: Tween

@onready var corpo: AnimatedSprite2D = $Corpo
@onready var cabeca: AnimatedSprite2D = $Cabeca
@onready var colisao: CollisionShape2D = $CollisionShape2D


## Chamado pelo manager logo depois do add_child().
func configurar(manager: Node2D, textura: Texture2D, matiz: float, brilho: float, celula: Vector2i) -> void:
	m = manager
	cel = celula
	velocidade = randf_range(m.velocidade_min, m.velocidade_max)
	var frames := Sprites.montar(textura)
	corpo.sprite_frames = frames["corpo"]
	cabeca.sprite_frames = frames["cabeca"]
	Sprites.posicionar(corpo, cabeca)
	if textura.resource_path == TEXTURA_PADRAO:
		# só varia a cor quando está usando o sprite padrão
		var mat := Sprites.material_cor(matiz, brilho)
		corpo.material = mat
		cabeca.material = mat
	direcao = DIRECOES[randi() % 4]
	m.ocupado[cel] = self
	_anim(false)


func iniciar_andando(espera: float) -> void:
	_parar(espera)


func iniciar_sentado(a) -> void:
	assento = a
	m.ocupado.erase(cel)
	global_position = a.pos
	estado = Estado.SENTADO
	_timer = randf_range(m.sentar_min, m.sentar_max) * randf_range(0.2, 1.0)
	_olhar_dir(a.dir)
	_anim(false)
	colisao.set_deferred("disabled", true)


func esta_sentado() -> bool:
	return estado == Estado.SENTADO or estado == Estado.SENTANDO


func _exit_tree() -> void:
	if is_instance_valid(m):
		m.liberar_npc(self)


func _process(delta: float) -> void:
	match estado:
		Estado.PARADO:
			_timer -= delta
			if _timer <= 0.0:
				_decidir()
		Estado.ESPERANDO:
			_timer -= delta
			if _timer <= 0.0:
				_iniciar_passo()
		Estado.ANDANDO:
			_mover(delta)
		Estado.SENTADO:
			_timer -= delta
			if _timer <= 0.0 or m.deve_levantar(delta):
				_levantar()


# ------------------------------------------------------------------ decisões

func _decidir() -> void:
	if m.quer_sentar():
		var a = m.reservar_assento(self)
		if a != null:
			assento = a
			if _planejar(a.acesso):
				return
			m.liberar_assento(a)
			assento = null
	var destino: Vector2i = m.destino_aleatorio(cel)
	if destino != cel and _planejar(destino):
		return
	_parar(randf_range(0.8, 2.0))


func _planejar(destino: Vector2i) -> bool:
	if destino == cel:
		_caminho.clear()
		_chegou()
		return true
	var c: Array[Vector2i] = m.achar_caminho(cel, destino)
	if c.size() < 2:
		return false
	_caminho = c
	_idx = 1
	_tentativas = 0
	_iniciar_passo()
	return true


func _iniciar_passo() -> void:
	var prox := _caminho[_idx]
	if not m.celula_livre_para(prox, self):
		_tentativas += 1
		if _tentativas > 6:
			_cancelar_rota()
		else:
			estado = Estado.ESPERANDO
			_timer = randf_range(0.25, 0.6)
			_anim(false)
		return
	_tentativas = 0
	m.ocupado[prox] = self
	_alvo = m.celula_global(prox)
	_olhar(_alvo - global_position)
	estado = Estado.ANDANDO
	_anim(true)


func _mover(delta: float) -> void:
	if m.jogador_no_caminho(_alvo, global_position):
		estado = Estado.ESPERANDO  # jogador entrou na frente: para e tenta de novo
		_timer = 0.3
		_anim(false)
		return
	var d := _alvo - global_position
	var passo := velocidade * delta
	if d.length() <= passo:
		global_position = _alvo
		if m.ocupado.get(cel) == self:
			m.ocupado.erase(cel)
		cel = _caminho[_idx]
		_idx += 1
		if _idx >= _caminho.size():
			_chegou()
		else:
			_iniciar_passo()
	else:
		global_position += d.normalized() * passo


func _cancelar_rota() -> void:
	if assento != null:
		m.liberar_assento(assento)
		assento = null
	_parar(randf_range(0.5, 1.5))


func _chegou() -> void:
	if assento != null:
		_sentar()
	else:
		_parar(randf_range(1.0, 4.5))


func _parar(tempo: float) -> void:
	estado = Estado.PARADO
	_timer = tempo
	if randf() < 0.5:
		direcao = DIRECOES[randi() % 4]
	_anim(false)


# ------------------------------------------------------------------ sentar / levantar

func _sentar() -> void:
	estado = Estado.SENTANDO
	_olhar(assento.pos - global_position)
	_anim(false)
	_tween = create_tween()
	_tween.tween_property(self, "global_position", assento.pos, 0.35)
	_tween.tween_callback(_ao_sentar)


func _ao_sentar() -> void:
	estado = Estado.SENTADO
	_timer = randf_range(m.sentar_min, m.sentar_max)
	_olhar_dir(assento.dir)
	_anim(false)
	if m.ocupado.get(cel) == self:
		m.ocupado.erase(cel)
	colisao.set_deferred("disabled", true)


func _levantar() -> void:
	var acesso: Vector2i = assento.acesso
	if not m.celula_livre_para(acesso, self):
		_timer = 0.4  # alguém está na frente; tenta de novo já já
		return
	estado = Estado.LEVANTANDO
	cel = acesso
	m.ocupado[cel] = self
	colisao.set_deferred("disabled", false)
	_olhar(m.celula_global(cel) - global_position)
	_tween = create_tween()
	_tween.tween_property(self, "global_position", m.celula_global(cel), 0.35)
	_tween.tween_callback(_ao_levantar)


func _ao_levantar() -> void:
	m.liberar_assento(assento)
	assento = null
	_parar(randf_range(0.5, 2.0))


## Some devagar (usado quando a densidade diminui e não há como remover fora da tela).
func desvanecer() -> void:
	if removendo:
		return
	removendo = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 1.0)
	t.tween_callback(m.remover.bind(self))


# ------------------------------------------------------------------ animação

func _olhar(v: Vector2) -> void:
	if v.length_squared() < 0.01:
		return
	if absf(v.x) > absf(v.y):
		direcao = "direita" if v.x > 0.0 else "esquerda"
	else:
		direcao = "baixo" if v.y > 0.0 else "cima"


func _olhar_dir(d: String) -> void:
	if d in DIRECOES:
		direcao = d


func _anim(andando: bool) -> void:
	Sprites.tocar(corpo, cabeca, ("andar_" if andando else "parado_") + direcao)
