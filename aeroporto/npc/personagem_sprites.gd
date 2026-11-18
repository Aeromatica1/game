extends RefCounted
## Monta as animações de um personagem 32x32 (spritesheet de 4 colunas x 8 linhas) dividido em DUAS partes:
##   - "corpo"  : da linha `linha_divisao` para baixo
##   - "cabeca" : da linha 0 até `linha_divisao` (cabelo/chapéu + rosto)
## A cabeça é desenhada num z_index maior que o corpo, então quando dois personagens se
## sobrepõem (jogador x NPC x NPC), as cabeças nunca ficam escondidas atrás do corpo do outro.
##
## Layout dos spritesheets (assets/airport_npcs_improved_4x/.../spritesheets, 128x256 px):
##   Linhas:  0-3 = andar (baixo, cima, esquerda, direita) | 4-7 = correr (mesma ordem)
##   Colunas: 4 quadros do ciclo (o quadro 0 também serve de "parado")
##
## Usamos os PNGs 32x32 originais: a versão "upscaled_4x" é só ampliação por vizinho mais próximo
## (mesmos pixels), então no jogo o resultado é idêntico ao escalar o original em 2x, com arquivos menores.

const TAMANHO := Vector2i(32, 32)
const DIRECOES := ["baixo", "esquerda", "cima", "direita"]
## Linha de cada direção no spritesheet (as de correr ficam 4 linhas abaixo).
const LINHA_DIRECAO := {"baixo": 0, "cima": 1, "esquerda": 2, "direita": 3}
const LINHAS_ANDAR := 4
## Linha (em px do sprite) onde a cabeça termina (cabelo/chapéu + rosto).
const LINHA_PADRAO := 20
## Escala no jogo: 2x inteiro mantém os pixels nítidos e deixa o personagem (~58 px de altura)
## do mesmo tamanho dos sprites antigos (~56 px).
const ESCALA_PADRAO := 2.0
## Y (em px do sprite) do último pixel dos pés dentro da célula de 32.
const PES_Y := 31
## Altura, em px de tela, em que os pés ficam em relação à origem do nó (mesmo valor do sprite antigo).
const PES_TELA := 4.0

const PASTA_PERSONAGENS := "res://assets/airport_characters/spritesheets/"

## Elenco. `sexo`: "m"/"f". `papel`: "jogador", "funcionario" ou "passageiro".
## `peso`: chance relativa de sorteio dentro do papel. Funcionários: mais staff/employee e
## poucos pilotos (como num aeroporto real); homens e mulheres somam 50/50 em cada papel.
const PERSONAGENS := {
	"businessman_m": {"sexo": "m", "papel": "jogador", "peso": 0},
	"businesswoman_f": {"sexo": "f", "papel": "jogador", "peso": 0},
	"employee_m": {"sexo": "m", "papel": "funcionario", "peso": 35},
	"pilot_m": {"sexo": "m", "papel": "funcionario", "peso": 15},
	"staff_f": {"sexo": "f", "papel": "funcionario", "peso": 30},
	"service_f": {"sexo": "f", "papel": "funcionario", "peso": 20},
	"passenger_m": {"sexo": "m", "papel": "passageiro", "peso": 1},
	"tourist_m": {"sexo": "m", "papel": "passageiro", "peso": 1},
	"passenger_f": {"sexo": "f", "papel": "passageiro", "peso": 1},
	"tourist_f": {"sexo": "f", "papel": "passageiro", "peso": 1},
}

const SHADER_COR := """
shader_type canvas_item;
uniform float deslocamento_matiz = 0.0;
uniform float brilho = 1.0;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void fragment() {
	vec4 cor = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(cor.rgb);
	float peso = smoothstep(0.30, 0.50, hsv.y);
	hsv.x = fract(hsv.x + deslocamento_matiz * peso);
	hsv.z = clamp(hsv.z * brilho, 0.0, 1.0);
	COLOR = vec4(hsv2rgb(hsv), cor.a);
}
"""

static var _cache: Dictionary = {}
static var _cache_espelhado: Dictionary = {}
static var _shader: Shader


## Spritesheet de um personagem do elenco (ex.: "staff_f").
static func textura_de(id: String) -> Texture2D:
	return load(PASTA_PERSONAGENS + id + ".png") as Texture2D


## Sorteia um personagem do papel ("funcionario" ou "passageiro") respeitando os pesos.
static func sortear(papel: String) -> String:
	var total := 0
	for id in PERSONAGENS:
		if PERSONAGENS[id].papel == papel:
			total += int(PERSONAGENS[id].peso)
	var r := randi() % maxi(total, 1)
	for id in PERSONAGENS:
		if PERSONAGENS[id].papel == papel:
			r -= int(PERSONAGENS[id].peso)
			if r < 0:
				return id
	return "passenger_m"


## Retorna {"corpo": SpriteFrames, "cabeca": SpriteFrames}. Resultado em cache (compartilhado).
static func montar(textura: Texture2D, linha_divisao: int = LINHA_PADRAO, com_correr: bool = false,
		fps_andar: float = 8.0, fps_correr: float = 12.0) -> Dictionary:
	var chave := [textura, linha_divisao, com_correr, fps_andar, fps_correr]
	if _cache.has(chave):
		return _cache[chave]
	# As linhas "direita" do spritesheet saem viradas para a esquerda: usamos as da esquerda espelhadas.
	var folha := _com_direita_espelhada(textura)
	var r := {
		"corpo": _montar_parte(folha, linha_divisao, TAMANHO.y, com_correr, fps_andar, fps_correr),
		"cabeca": _montar_parte(folha, 0, linha_divisao, com_correr, fps_andar, fps_correr),
	}
	_cache[chave] = r
	return r


## Posiciona as duas metades para que, juntas, ocupem o mesmo lugar que o sprite inteiro
## ocuparia, com os pés em `PES_TELA` (o mesmo ponto de apoio dos sprites antigos).
static func posicionar(corpo: Node2D, cabeca: Node2D, linha_divisao: int = LINHA_PADRAO,
		escala: float = ESCALA_PADRAO) -> void:
	var topo := PES_TELA - (PES_Y + 1) * escala
	cabeca.position = Vector2(0.0, topo + linha_divisao * escala * 0.5)
	corpo.position = Vector2(0.0, topo + linha_divisao * escala + (TAMANHO.y - linha_divisao) * escala * 0.5)
	corpo.scale = Vector2(escala, escala)
	cabeca.scale = Vector2(escala, escala)
	cabeca.z_index = 1 # cabeça sempre acima de qualquer corpo do mesmo nível


## Toca a mesma animação nas duas partes, mantendo-as sincronizadas.
static func tocar(corpo: AnimatedSprite2D, cabeca: AnimatedSprite2D, nome: String) -> void:
	if corpo.animation != nome or not corpo.is_playing():
		corpo.play(nome)
		cabeca.play(nome)
		cabeca.set_frame_and_progress(corpo.frame, corpo.frame_progress)


static func material_cor(matiz: float, brilho: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_COR
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("deslocamento_matiz", matiz)
	mat.set_shader_parameter("brilho", brilho)
	return mat


## Cópia do spritesheet em que as linhas da direita (andar e correr) são as da esquerda espelhadas
## horizontalmente, quadro a quadro. Assim os dois lados ficam sempre consistentes.
static func _com_direita_espelhada(textura: Texture2D) -> Texture2D:
	if _cache_espelhado.has(textura):
		return _cache_espelhado[textura]
	var img := textura.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var colunas := img.get_width() / TAMANHO.x
	for base in [0, LINHAS_ANDAR]:
		var y_esq: int = (base + LINHA_DIRECAO["esquerda"]) * TAMANHO.y
		var y_dir: int = (base + LINHA_DIRECAO["direita"]) * TAMANHO.y
		for c in colunas:
			var quadro := img.get_region(Rect2i(c * TAMANHO.x, y_esq, TAMANHO.x, TAMANHO.y))
			quadro.flip_x()
			img.blit_rect(quadro, Rect2i(0, 0, TAMANHO.x, TAMANHO.y), Vector2i(c * TAMANHO.x, y_dir))
	var tex := ImageTexture.create_from_image(img)
	_cache_espelhado[textura] = tex
	return tex


static func _montar_parte(textura: Texture2D, y0: int, y1: int, com_correr: bool,
		fps_andar: float, fps_correr: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var altura := y1 - y0
	for dir: String in DIRECOES:
		var linha: int = LINHA_DIRECAO[dir]
		frames.add_animation("parado_" + dir)
		frames.set_animation_loop("parado_" + dir, false)
		frames.add_frame("parado_" + dir, _frame(textura, 0, linha, y0, altura))
		frames.add_animation("andar_" + dir)
		frames.set_animation_speed("andar_" + dir, fps_andar)
		for coluna in 4:
			frames.add_frame("andar_" + dir, _frame(textura, coluna, linha, y0, altura))
		if com_correr:
			frames.add_animation("correr_" + dir)
			frames.set_animation_speed("correr_" + dir, fps_correr)
			for coluna in 4:
				frames.add_frame("correr_" + dir, _frame(textura, coluna, linha + LINHAS_ANDAR, y0, altura))
	return frames


static func _frame(textura: Texture2D, coluna: int, linha: int, y0: int, altura: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = textura
	atlas.region = Rect2(coluna * TAMANHO.x, linha * TAMANHO.y + y0, TAMANHO.x, altura)
	return atlas
