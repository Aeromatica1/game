extends RefCounted
## Monta as animações de um personagem 28x28 (6 colunas x 4 linhas) dividido em DUAS partes:
##   - "corpo"  : da linha `linha_divisao` para baixo
##   - "cabeca" : da linha 0 até `linha_divisao` (cabelo/chapéu + rosto)
## A cabeça é desenhada num z_index maior que o corpo, então quando dois personagens se
## sobrepõem (jogador x NPC x NPC), as cabeças nunca ficam escondidas atrás do corpo do outro.
##
## Layout do spritesheet:
##   Linhas:  0 = baixo, 1 = esquerda, 2 = cima, 3 = direita
##   Colunas: 0-2 = andar (parado, passo A, passo B) | 3-5 = correr (parado, passo A, passo B)

const TAMANHO := Vector2i(28, 28)
const DIRECOES := ["baixo", "esquerda", "cima", "direita"]
## Linha (em px do sprite) onde a cabeça termina. O sprite novo tem chapéu+rosto até ~y=19.
const LINHA_PADRAO := 19

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
static var _shader: Shader


## Retorna {"corpo": SpriteFrames, "cabeca": SpriteFrames}. Resultado em cache (compartilhado).
static func montar(textura: Texture2D, linha_divisao: int = LINHA_PADRAO, com_correr: bool = false,
		fps_andar: float = 8.0, fps_correr: float = 12.0) -> Dictionary:
	var chave := [textura, linha_divisao, com_correr]
	if _cache.has(chave):
		return _cache[chave]
	var r := {
		"corpo": _montar_parte(textura, linha_divisao, TAMANHO.y, com_correr, fps_andar, fps_correr),
		"cabeca": _montar_parte(textura, 0, linha_divisao, com_correr, fps_andar, fps_correr),
	}
	_cache[chave] = r
	return r


## Posiciona as duas metades para que, juntas, ocupem o mesmo lugar que o sprite inteiro
## ocuparia (centrado em `base_y`, na `escala` dada).
static func posicionar(corpo: Node2D, cabeca: Node2D, linha_divisao: int = LINHA_PADRAO,
		base_y: float = -24.0, escala: float = 2.0) -> void:
	var topo := base_y - TAMANHO.y * escala * 0.5
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


static func _montar_parte(textura: Texture2D, y0: int, y1: int, com_correr: bool,
		fps_andar: float, fps_correr: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for linha in DIRECOES.size():
		var dir: String = DIRECOES[linha]
		var altura := y1 - y0
		frames.add_animation("parado_" + dir)
		frames.set_animation_loop("parado_" + dir, false)
		frames.add_frame("parado_" + dir, _frame(textura, 0, linha, y0, altura))
		frames.add_animation("andar_" + dir)
		frames.set_animation_speed("andar_" + dir, fps_andar)
		for coluna in [1, 0, 2, 0]:
			frames.add_frame("andar_" + dir, _frame(textura, coluna, linha, y0, altura))
		if com_correr:
			frames.add_animation("correr_" + dir)
			frames.set_animation_speed("correr_" + dir, fps_correr)
			for coluna in [4, 3, 5, 3]:
				frames.add_frame("correr_" + dir, _frame(textura, coluna, linha, y0, altura))
	return frames


static func _frame(textura: Texture2D, coluna: int, linha: int, y0: int, altura: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = textura
	atlas.region = Rect2(coluna * TAMANHO.x, linha * TAMANHO.y + y0, TAMANHO.x, altura)
	return atlas
