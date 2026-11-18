extends Node2D
## Cena Main (Node2D) com a cena do Grid instanciada como filha chamada "Grid".
## Coloque as imagens das peças em res://pecas/ (ou mude PECA_DIR).

## Emitido no game over quando o jogo está embutido no mapa (em vez de recarregar a cena).
signal fechar_pedido

const PECA_DIR := "res://assets/minigames/block_blast/"

## Faixa no topo reservada para a pontuação (o grid e a bandeja usam o resto da tela).
const TOPO_PONTOS := 64.0
const COR_PONTOS := Color(1.0, 0.85, 0.2)
const COR_DINHEIRO := Color(0.45, 1.0, 0.55)
## Palavras usadas para achar este minigame na tabela `tipo_minigame` do servidor
## (se o id for conhecido, é mais seguro preencher `tipo_minigame_id` no Inspector).
const PALAVRAS_TIPO := ["tetris", "block", "blast"]

# Formatos conferidos com a transparência das suas imagens (cada célula = 16 px).
const DEFS := {
	"--": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"I": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],
	"J": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	"L": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
	"O": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"S": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"T": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"Z": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
}

# ---------- tamanho e posição ----------
@export var escala_auto := true     # true: usa o maior zoom inteiro que cabe na janela
@export var escala := 3.0           # zoom manual (só vale se escala_auto = false)
@export var tamanho_bandeja := 0.5  # tamanho das peças na bandeja em relação ao grid
@export var espaco_bandeja := 14.0  # distância entre o grid e a bandeja (em px da arte)
## id deste minigame em `tipo_minigame` (servidor). -1 = procura pelo nome (PALAVRAS_TIPO).
@export var tipo_minigame_id := -1

@onready var grid: Grid = $Grid

var pecas: Array[Piece] = []
var nomes_validos: Array[String] = []   # só as peças cuja imagem foi encontrada
var pontos := 0
var fim := false
var saco: Array = []

var rotulo_pontos: Label     # número grande, no meio do topo
var rotulo_dinheiro: Label   # dinheiro do aeroporto (canto superior direito)
var fundo_fim: ColorRect     # escurece a tela no game over
var rotulo_fim_titulo: Label
var rotulo_fim_corpo: Label
var _tween_pontos: Tween
var _pago := false           # os pontos já foram convertidos em dinheiro?

func _ready() -> void:
	randomize()
	# deixa a pixel art nítida em tudo (grid, peças e blocos encaixados)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_criar_hud()
	_atualizar_pontos(false)
	tree_exiting.connect(_ao_sair)

	_verificar_imagens()
	if nomes_validos.is_empty():
		_mostrar_fim("Imagens não encontradas", "Nenhuma imagem em " + PECA_DIR + "\n(veja o painel Output)", Color(1, 0.6, 0.4))
		return

	_posicionar_grid()
	novas_pecas()


# Confere se cada imagem existe e avisa no painel Output qual está faltando.
func _verificar_imagens() -> void:
	nomes_validos.clear()
	for nome in DEFS.keys():
		var caminho: String = PECA_DIR + nome + ".png"
		if ResourceLoader.exists(caminho):
			nomes_validos.append(nome)
		else:
			push_error("Imagem NÃO encontrada: " + caminho)


# Aumenta o grid e coloca ele (junto com a bandeja) no centro da janela.
func _posicionar_grid() -> void:
	var vp := get_viewport_rect().size
	var tam := grid.tamanho()
	var bandeja_h := 4.0 * grid.cell_size * tamanho_bandeja   # altura da maior peça na bandeja
	var altura_total := tam.y + espaco_bandeja + bandeja_h     # grid + bandeja, sem escala
	var area_y := vp.y - TOPO_PONTOS                           # o topo é da pontuação

	if escala_auto:
		# zoom inteiro sempre que der (pixel art nítida); se não couber, usa passos de 0,25
		var cabe := minf(vp.x / tam.x, area_y / altura_total)
		escala = floorf(cabe) if cabe >= 2.0 else maxf(1.0, floorf(cabe * 4.0) / 4.0)

	grid.scale = Vector2.ONE * escala
	grid.position = Vector2(
		(vp.x - tam.x * escala) / 2.0,
		TOPO_PONTOS + (area_y - altura_total * escala) / 2.0)

var ultimos_tres: Array = []

func geracao_pseudoaleatoria() -> String:
	var candidatas: Array = []
	for n in nomes_validos:
		if n not in saco and n not in ultimos_tres:
			candidatas.append(n)

	if candidatas.is_empty():
		for n in nomes_validos:
			if n not in saco:
				candidatas.append(n)

	var nome: String = candidatas.pick_random()

	saco.append(nome)
	ultimos_tres.append(nome)
	if ultimos_tres.size() > 3:
		ultimos_tres.remove_at(0)

	if saco.size() == nomes_validos.size():
		saco.clear()

	return nome
	
func novas_pecas() -> void:
	# a bandeja usa a largura da área jogável, dividida em 3 espaços
	var area_x := grid.global_position.x + grid.origem.x * escala
	var area_largura := Grid.TAM * grid.cell_size * escala
	var slot_largura := area_largura / 3.0
	var bandeja_y := grid.global_position.y + (grid.tamanho().y + espaco_bandeja) * escala

	for i in 3:
		var nome: String = geracao_pseudoaleatoria()

		var p := Piece.new()
		add_child(p)
		p.home_scale = escala * tamanho_bandeja
		p.drag_escala = escala
		p.setup(load(PECA_DIR + nome + ".png"), DEFS[nome], grid.cell_size)

		# centraliza a peça dentro do seu espaço da bandeja
		var largura_peca := p.bbox.x * grid.cell_size * p.home_scale
		p.home_position = Vector2(
			area_x + i * slot_largura + (slot_largura - largura_peca) / 2.0,
			bandeja_y)
		p.global_position = p.home_position
		p.movendo.connect(_on_movendo)
		p.soltou.connect(_on_soltou)
		pecas.append(p)

	_checar_game_over()


func _celula_da_peca(p: Piece) -> Vector2i:
	# usa o canto superior esquerdo da peça, arredondando para a célula mais próxima
	var meia := Vector2.ONE * grid.cell_size * escala / 2.0
	return grid.pos_para_celula(p.global_position + meia)


func _on_movendo(p: Piece) -> void:
	grid.set_preview(p.cells, _celula_da_peca(p))


func _on_soltou(p: Piece) -> void:
	grid.limpar_preview()
	if fim:
		return

	var cel := _celula_da_peca(p)
	if grid.pode_colocar(p.cells, cel):
		# o grid passa a desenhar os pedaços da SUA arte nas células
		grid.colocar(p.cells, cel, p.texturas_das_celulas())
		pontos += p.cells.size()

		var linhas := grid.limpar_linhas()
		if linhas > 0:
			pontos += linhas * 10 * linhas   # combo: mais linhas de uma vez = mais pontos
		_atualizar_pontos()

		pecas.erase(p)
		p.queue_free()

		if pecas.is_empty():
			novas_pecas()
		else:
			_checar_game_over()
	else:
		p.voltar()


func _checar_game_over() -> void:
	if fim:
		return
	for p in pecas:
		if grid.cabe_em_algum_lugar(p.cells):
			return
	fim = true
	_fim_de_jogo()


## Game over: mostra os pontos, converte em dinheiro (servidor) e fecha sozinho.
func _fim_de_jogo() -> void:
	_mostrar_fim("FIM DE JOGO", "Pontos: %d\nConvertendo em dinheiro..." % pontos, Color.WHITE)
	var resultado: Array = await _pagar_pontos()
	_mostrar_fim("FIM DE JOGO", resultado[0], resultado[1])
	await _esperar(3.0)
	if has_meta("embutido"):
		fechar_pedido.emit()
	else:
		get_tree().reload_current_scene()


## Espera sem depender do SceneTree: se o jogo for fechado antes, o Timer morre junto
## e nada tenta continuar uma função de um nó que já não existe.
func _esperar(segundos: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	add_child(t)
	t.start(segundos)
	await t.timeout
	t.queue_free()


# =============================================================================
#  Pontos -> dinheiro
# =============================================================================

func _tipo_id() -> int:
	if tipo_minigame_id >= 0:
		return tipo_minigame_id
	return GameState.tipo_minigame_id(PALAVRAS_TIPO)


## Envia os pontos ao servidor (que credita o dinheiro e guarda o recorde).
## Retorna [texto, cor] para mostrar ao jogador. O ganho mostrado é a diferença REAL de
## dinheiro depois da resposta do servidor, então a tela nunca promete mais do que foi pago.
func _pagar_pontos() -> Array:
	_pago = true
	var base := "Pontos: %d" % pontos
	if pontos <= 0:
		return [base, Color.WHITE]
	if GameState.aeroporto_id == "":
		return [base + "\n(sem save carregado: dinheiro não creditado)", Color(1, 0.8, 0.4)]
	var tipo := _tipo_id()
	if tipo < 0:
		push_warning("Block Blast: não achei o tipo de minigame no servidor. Preencha `tipo_minigame_id` em Main.tscn. Tipos recebidos: %s" % str(GameState.tipos_minigame))
		return [base + "\n(minigame não cadastrado no servidor)", Color(1, 0.8, 0.4)]

	var antes := GameState.dinheiro()
	var r: Dictionary = await GameState.concluir_minigame(tipo, float(pontos))
	if not r.ok:
		return [base + "\nNão foi possível creditar: %s" % str(r.error), Color(1, 0.55, 0.55)]
	var ganho := GameState.dinheiro() - antes
	if ganho > 0.0:
		return [base + "\nVocê ganhou +%s" % GameState.formatar_dinheiro(ganho), COR_DINHEIRO]
	return [base + "\nPontuação registrada", Color.WHITE]


## Saiu no meio da partida (Esc / Fechar): os pontos feitos até ali também viram dinheiro.
## A chamada roda no autoload GameState, então continua mesmo com este nó já destruído.
func _ao_sair() -> void:
	if _pago or pontos <= 0 or GameState.aeroporto_id == "":
		return
	var tipo := _tipo_id()
	if tipo < 0:
		return
	_pago = true
	GameState.concluir_minigame(tipo, float(pontos))


# =============================================================================
#  HUD
# =============================================================================

func _novo_rotulo(tamanho: int, cor: Color, contorno: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", tamanho)
	l.add_theme_color_override("font_color", cor)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", contorno)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _criar_hud() -> void:
	var vp := get_viewport_rect().size

	# pontuação: só o número, no meio (horizontal) do topo da tela
	rotulo_pontos = _novo_rotulo(42, COR_PONTOS, 6)
	rotulo_pontos.position = Vector2(0, 8)
	rotulo_pontos.size = Vector2(vp.x, 50)
	rotulo_pontos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(rotulo_pontos)

	# dinheiro do aeroporto (só com um save carregado): mostra os pontos virando dinheiro
	rotulo_dinheiro = _novo_rotulo(18, COR_DINHEIRO, 5)
	rotulo_dinheiro.position = Vector2(0, 8)
	rotulo_dinheiro.size = Vector2(vp.x - 14.0, 24)
	rotulo_dinheiro.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rotulo_dinheiro.visible = GameState.aeroporto_id != "" and not has_meta("embutido")
	add_child(rotulo_dinheiro)
	_atualizar_dinheiro(GameState.dinheiro())
	GameState.dinheiro_mudou.connect(_atualizar_dinheiro)

	# tela de game over (escurece tudo e escreve no centro)
	fundo_fim = ColorRect.new()
	fundo_fim.color = Color(0, 0, 0, 0.7)
	fundo_fim.size = vp
	fundo_fim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo_fim.z_index = 100
	fundo_fim.visible = false
	add_child(fundo_fim)

	rotulo_fim_titulo = _novo_rotulo(44, Color(1, 0.4, 0.35), 6)
	rotulo_fim_titulo.position = Vector2(0, vp.y / 2.0 - 130.0)
	rotulo_fim_titulo.size = Vector2(vp.x, 70)
	rotulo_fim_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fundo_fim.add_child(rotulo_fim_titulo)

	rotulo_fim_corpo = _novo_rotulo(26, Color.WHITE, 5)
	rotulo_fim_corpo.position = Vector2(0, vp.y / 2.0 - 40.0)
	rotulo_fim_corpo.size = Vector2(vp.x, 140)
	rotulo_fim_corpo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fundo_fim.add_child(rotulo_fim_corpo)


func _mostrar_fim(titulo: String, corpo: String, cor: Color) -> void:
	rotulo_fim_titulo.text = titulo
	rotulo_fim_corpo.text = corpo
	rotulo_fim_corpo.add_theme_color_override("font_color", cor)
	fundo_fim.visible = true


## Atualiza o número grande; a cada mudança ele dá uma "puladinha" para chamar a atenção.
func _atualizar_pontos(animar: bool = true) -> void:
	rotulo_pontos.text = str(pontos)
	if not animar:
		return
	rotulo_pontos.pivot_offset = rotulo_pontos.size / 2.0
	if _tween_pontos and _tween_pontos.is_valid():
		_tween_pontos.kill()
	_tween_pontos = create_tween()
	_tween_pontos.tween_property(rotulo_pontos, "scale", Vector2.ONE * 1.25, 0.08)
	_tween_pontos.tween_property(rotulo_pontos, "scale", Vector2.ONE, 0.14)


func _atualizar_dinheiro(valor: float) -> void:
	if rotulo_dinheiro:
		rotulo_dinheiro.text = "Dinheiro: %s" % GameState.formatar_dinheiro(valor)
