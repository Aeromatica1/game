extends Node2D
## Cena Main (Node2D) com a cena do Grid instanciada como filha chamada "Grid".
## Coloque as imagens das peças em res://pecas/ (ou mude PECA_DIR).

const PECA_DIR := "res://Assets/pecas/"

# Formatos conferidos com a transparência das suas imagens (cada célula = 16 px).
const DEFS := {
	"--": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"I": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],
	"J": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	"L": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
	"Quadrado": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"S": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"T": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"z": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
}

# ---------- tamanho e posição ----------
@export var escala_auto := true     # true: usa o maior zoom inteiro que cabe na janela
@export var escala := 3.0           # zoom manual (só vale se escala_auto = false)
@export var tamanho_bandeja := 0.5  # tamanho das peças na bandeja em relação ao grid
@export var espaco_bandeja := 14.0  # distância entre o grid e a bandeja (em px da arte)

@onready var grid: Grid = $Grid

var pecas: Array[Piece] = []
var nomes_validos: Array[String] = []   # só as peças cuja imagem foi encontrada
var pontos := 0
var fim := false
var label: Label
var saco: Array = []

func _ready() -> void:
	randomize()
	# deixa a pixel art nítida em tudo (grid, peças e blocos encaixados)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	label = Label.new()
	label.position = Vector2(4, 4)
	add_child(label)
	_atualizar_label()

	_verificar_imagens()
	if nomes_validos.is_empty():
		label.text = "Nenhuma imagem encontrada em " + PECA_DIR + " (veja o painel Output)"
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

	if escala_auto:
		escala = maxf(1.0, floorf(minf(vp.x / tam.x, vp.y / altura_total)))

	grid.scale = Vector2.ONE * escala
	grid.position = Vector2(
		(vp.x - tam.x * escala) / 2.0,
		(vp.y - altura_total * escala) / 2.0)

var ultimos_tres: Array = []

func geracao_pseudoaleatoria() -> String:
	var candidatas: Array = []
	for n in nomes_validos:
		if n not in saco and n not in ultimos_tres:
			candidatas.append(n)

	# segurança: se o filtro dos últimos três esvaziar a lista, ignora ele
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
		_atualizar_label()

		pecas.erase(p)
		p.queue_free()

		if pecas.is_empty():
			novas_pecas()
		else:
			_checar_game_over()
	else:
		p.voltar()


func _checar_game_over() -> void:
	for p in pecas:
		if grid.cabe_em_algum_lugar(p.cells):
			return
	fim = true
	label.text = "GAME OVER  -  Pontos: %d" % pontos
	await get_tree().create_timer(2.5).timeout
	get_tree().reload_current_scene()


func _atualizar_label() -> void:
	label.text = "Pontos: %d" % pontos
