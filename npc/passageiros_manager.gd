extends Node2D
## Gerenciador dos passageiros (NPCs) do aeroporto.
##
## >>> Para controlar o fluxo, mude a variável `densidade` (1 a 10) <<<
##   - no Inspector, selecionando o nó "Passageiros" em Mundo; ou
##   - por código:  get_tree().call_group("passageiros", "definir_densidade", 7)
##   - em tempo de jogo: PageUp / PageDown (desligue em `teclas_de_atalho`).
##
## Como funciona:
##   * Lê o TileMapLayer do chão e descobre sozinho onde dá para andar
##     (tiles com navegação + tiles das fontes em `fontes_caminhaveis`), tirando as
##     células ocupadas por qualquer corpo físico (balcões, bancos, poltronas, janelas...).
##   * Monta uma grade A* e os NPCs andam célula a célula (estilo Pokémon).
##   * Procura sozinho todos os assentos (poltronas e bancos) e cria os lugares onde
##     os NPCs sentam. Cada fileira vira N lugares (largura / `assento_largura`).
##   * Mantém a população conforme a densidade: nasce/some fora da tela.
##   * F3 mostra os assentos (verde = livre, vermelho = ocupado) e F4 a grade andável,
##     úteis para ajustar `assento_deslocamento` e `assento_largura`.

const NpcScene := preload("res://npc/npc.tscn")
const NpcScript := preload("res://npc/npc.gd")

## Passageiros andando por 1000 px de corredor, para cada nível (índice 0 = nível 1).
const CAMINHANTES_POR_1000PX: Array[float] = [0.4, 0.9, 1.6, 2.4, 3.4, 4.6, 6.0, 7.6, 9.4, 11.5]
## Fração dos assentos que fica ocupada, para cada nível.
const FRACAO_ASSENTOS: Array[float] = [0.05, 0.12, 0.22, 0.32, 0.43, 0.54, 0.65, 0.75, 0.85, 0.93]

signal densidade_mudou(valor: int)

## Fluxo/densidade de passageiros: 1 = aeroporto quase vazio, 10 = lotado.
@export_range(1, 10) var densidade: int = 3:
	set(valor):
		var novo := clampi(valor, 1, 10)
		if novo == densidade:
			return
		densidade = novo
		if _pronto:
			_ao_mudar_densidade()

@export_group("Referências")
@export var chao: TileMapLayer
@export var jogador: Node2D

@export_group("Grade")
## IDs de fontes (TileSetAtlasSource) cujos tiles são chão andável mesmo sem polígono de navegação.
@export var fontes_caminhaveis: Array[int] = [3]
## Regiões andáveis isoladas menores que isto (em células) são ignoradas.
@export var tamanho_minimo_regiao: int = 40

@export_group("NPCs")
## Se vazio, usa o sprite do jogador com cores variadas. Se preencher, use spritesheets
## no mesmo formato (6x4, células 28x28) e eles são sorteados.
@export var texturas_npc: Array[Texture2D] = []
@export var velocidade_min: float = 70.0
@export var velocidade_max: float = 110.0
## Quanto tempo (s) um passageiro fica sentado, no mínimo e no máximo.
@export var sentar_min: float = 25.0
@export var sentar_max: float = 90.0
@export var maximo_de_npcs: int = 220
## 0 = aleatório a cada partida; outro valor = sempre a mesma população inicial.
@export var semente: int = 0

@export_group("Assentos")
## Largura de um lugar, em px, para dividir cada fileira de poltronas.
@export var assento_largura: float = 48.0
## Onde ficam os pés do NPC em relação ao centro do lugar. Ajuste olhando o F3.
@export var assento_deslocamento: Vector2 = Vector2(0, 20)
@export_enum("baixo", "esquerda", "cima", "direita") var direcao_sentado: String = "baixo"

@export_group("Atalhos / Depuração")
@export var teclas_de_atalho: bool = true
@export var mostrar_hud: bool = true

class Assento:
	var pos: Vector2          # onde os pés do NPC ficam sentado
	var centro: Vector2       # centro do lugar
	var dir: String           # para onde olha sentado
	var acesso: Vector2i      # célula do chão de onde se entra/sai
	var ocupante = null

## célula -> Npc que a ocupa (ou está indo para ela). Usado pelos NPCs.
var ocupado: Dictionary = {}
var alvo_sentados: int = 0
var alvo_caminhantes: int = 0

var _pronto := false
var _astar := AStarGrid2D.new()
var _livres: Dictionary = {}              # Vector2i -> true
var _lista_livres: Array[Vector2i] = []
var _regiao := Rect2i()
var _tam := Vector2(32, 32)
var _assentos: Array[Assento] = []
var _reservados := 0
var _npcs: Array = []
var _acum := 0.0
var _excesso_t := 0.0
var _largura_px := 1000.0
var _debug_assentos := false
var _debug_grade := false
var _hud: Label
var _hud_tween: Tween


func _ready() -> void:
	add_to_group("passageiros")
	z_index = 100
	if semente != 0:
		seed(semente)
	else:
		randomize()
	_criar_hud()
	# espera o mundo de física registrar os corpos estáticos antes de testar colisões
	await get_tree().physics_frame
	await get_tree().physics_frame
	_achar_referencias()
	if chao == null:
		push_error("Passageiros: defina a propriedade `chao` (TileMapLayer).")
		return
	_construir_grade()
	_coletar_assentos()
	_recalcular_alvos()
	_pronto = true
	_povoar_inicial()
	print("[Passageiros] células andáveis: %d | assentos: %d | densidade %d -> %d sentados + %d andando"
		% [_lista_livres.size(), _assentos.size(), densidade, alvo_sentados, alvo_caminhantes])


## Se `chao`/`jogador` não estiverem ligados no Inspector (ex.: o nó foi movido/renomeado),
## procura sozinho: o TileMapLayer "Chão" (ou o com mais tiles) e o nó "Player".
func _achar_referencias() -> void:
	var pai := get_parent()
	if chao == null:
		var melhor: TileMapLayer = null
		var melhor_n := -1
		for c in get_tree().root.find_children("*", "TileMapLayer", true, false):
			if c.name == &"Chão":
				melhor = c
				break
			var n: int = c.get_used_cells().size()
			if n > melhor_n:
				melhor_n = n
				melhor = c
		chao = melhor
	if jogador == null:
		jogador = pai.get_node_or_null("Player") as Node2D
		if jogador == null:
			var achados := get_tree().root.find_children("Player", "Node2D", true, false)
			if not achados.is_empty():
				jogador = achados[0]


func definir_densidade(valor: int) -> void:
	densidade = valor


func total_de_npcs() -> int:
	return _npcs.size()


# ------------------------------------------------------------------ grade e assentos

func _construir_grade() -> void:
	_tam = Vector2(chao.tile_set.tile_size)
	var espaco := get_world_2d().direct_space_state
	var forma := RectangleShape2D.new()
	forma.size = _tam - Vector2(8, 8)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = forma
	q.collision_mask = 1 | 8 # cenário (camada 1) + funcionários (camada 4); jogador é camada 2
	# (a grade é montada antes de os passageiros nascerem, então eles não entram aqui)

	var candidatas: Dictionary = {}
	for c in chao.get_used_cells():
		if not _celula_andavel(c):
			continue
		q.transform = Transform2D(0.0, celula_global(c))
		if espaco.intersect_shape(q, 1).is_empty():
			candidatas[c] = true

	# fica só com a maior região conectada (evita NPCs em ilhas inalcançáveis)
	var visitadas: Dictionary = {}
	var melhor: Array[Vector2i] = []
	for c in candidatas:
		if visitadas.has(c):
			continue
		var regiao: Array[Vector2i] = []
		var fila: Array[Vector2i] = [c]
		visitadas[c] = true
		while not fila.is_empty():
			var atual: Vector2i = fila.pop_back()
			regiao.append(atual)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var v: Vector2i = atual + d
				if candidatas.has(v) and not visitadas.has(v):
					visitadas[v] = true
					fila.append(v)
		if regiao.size() > melhor.size():
			melhor = regiao
	if melhor.size() < tamanho_minimo_regiao:
		push_warning("Passageiros: região andável muito pequena (%d células)." % melhor.size())

	_livres.clear()
	_lista_livres = melhor
	var minimo := Vector2i(1 << 30, 1 << 30)
	var maximo := Vector2i(-(1 << 30), -(1 << 30))
	for c in melhor:
		_livres[c] = true
		minimo = minimo.min(c)
		maximo = maximo.max(c)
	if melhor.is_empty():
		return
	_regiao = Rect2i(minimo, maximo - minimo + Vector2i.ONE)
	_largura_px = _regiao.size.x * _tam.x

	_astar.region = _regiao
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	for x in range(_regiao.position.x, _regiao.end.x):
		for y in range(_regiao.position.y, _regiao.end.y):
			var c := Vector2i(x, y)
			if not _livres.has(c):
				_astar.set_point_solid(c, true)


func _celula_andavel(c: Vector2i) -> bool:
	var td := chao.get_cell_tile_data(c)
	if td == null:
		return false
	if chao.tile_set.get_physics_layers_count() > 0 and td.get_collision_polygons_count(0) > 0:
		return false
	if chao.tile_set.get_navigation_layers_count() > 0 and td.get_navigation_polygon(0) != null:
		return true
	return chao.get_cell_source_id(c) in fontes_caminhaveis


func _coletar_assentos() -> void:
	var fontes: Array[Sprite2D] = []
	_achar_fontes(get_tree().root, fontes)
	for s in fontes:
		var largura: float = s.region_rect.size.x if s.region_enabled else float(s.texture.get_width())
		var n := maxi(1, roundi(largura / assento_largura))
		var passo := largura / n
		for i in n:
			var centro := s.to_global(Vector2(-largura * 0.5 + passo * (i + 0.5), 0.0))
			var a := Assento.new()
			a.centro = centro
			a.pos = centro + assento_deslocamento
			a.dir = String(s.get_meta("direcao_assento", direcao_sentado))
			var acesso = _celula_mais_proxima(centro, 140.0)
			if acesso == null:
				continue
			a.acesso = acesso
			_assentos.append(a)


func _achar_fontes(no: Node, saida: Array[Sprite2D]) -> void:
	var caminho := no.scene_file_path
	if caminho.contains("poltrona_nivel"):
		for s in no.find_children("*", "Sprite2D", true, false):
			if _eh_fileira(s):
				saida.append(s)
		return
	if caminho.ends_with("/banco.tscn"):
		var s := no.get_node_or_null("Sprite2D") as Sprite2D
		if s != null and s.texture != null:
			saida.append(s)
		return
	for f in no.get_children():
		_achar_fontes(f, saida)


func _eh_fileira(s: Sprite2D) -> bool:
	return s.texture != null and s.region_enabled and s.region_rect.size.x >= assento_largura * 1.5


func _celula_mais_proxima(ponto: Vector2, max_dist: float):
	var melhor_d := max_dist
	var melhor = null
	for c in _lista_livres:
		var cg := celula_global(c)
		var d := cg.distance_to(ponto) + (0.0 if cg.y >= ponto.y else 12.0) # prefere entrar por baixo
		if d < melhor_d:
			melhor_d = d
			melhor = c
	return melhor


# ------------------------------------------------------------------ API usada pelos NPCs

func celula_global(c: Vector2i) -> Vector2:
	return chao.to_global(chao.map_to_local(c))


func achar_caminho(de: Vector2i, para: Vector2i) -> Array[Vector2i]:
	var r: Array[Vector2i] = []
	if _livres.has(de) and _livres.has(para):
		r.assign(_astar.get_id_path(de, para))
	return r


func celula_livre_para(c: Vector2i, npc: Node) -> bool:
	var o = ocupado.get(c)
	if o != null and o != npc and is_instance_valid(o):
		return false
	if jogador != null and jogador.global_position.distance_to(celula_global(c)) < 30.0:
		return false
	return true


## O jogador está perto do ponto para onde o NPC vai (ou colado nele)?
func jogador_no_caminho(alvo: Vector2, pos_npc: Vector2) -> bool:
	if jogador == null:
		return false
	var p := jogador.global_position
	return p.distance_to(alvo) < 28.0 and p.distance_to(pos_npc) < 56.0


func destino_aleatorio(de: Vector2i) -> Vector2i:
	var escolhido := de
	for i in 10:
		escolhido = _lista_livres[randi() % _lista_livres.size()]
		var dist := absi(escolhido.x - de.x) + absi(escolhido.y - de.y)
		if dist >= 5 and dist <= 70:
			break
	return escolhido


func quer_sentar() -> bool:
	return _reservados < alvo_sentados and randf() < 0.7


func deve_levantar(delta: float) -> bool:
	return _reservados > alvo_sentados and randf() < delta * 0.4


func reservar_assento(npc: Node) -> Assento:
	var livres: Array[Assento] = []
	for a in _assentos:
		if a.ocupante == null:
			livres.append(a)
	if livres.is_empty():
		return null
	# sorteia alguns e fica com o mais perto (evita atravessar o aeroporto toda hora)
	var melhor: Assento = null
	var melhor_d := INF
	for i in mini(6, livres.size()):
		var a: Assento = livres[randi() % livres.size()]
		var d := a.pos.distance_to(npc.global_position)
		if d < melhor_d:
			melhor_d = d
			melhor = a
	melhor.ocupante = npc
	_reservados += 1
	return melhor


func liberar_assento(a: Assento) -> void:
	if a != null and a.ocupante != null:
		a.ocupante = null
		_reservados -= 1


## Chamado quando o NPC sai da árvore (qualquer motivo): limpa células e assento.
func liberar_npc(npc: Node) -> void:
	_npcs.erase(npc)
	for c in ocupado.keys():
		if ocupado[c] == npc:
			ocupado.erase(c)
	if npc.assento != null:
		liberar_assento(npc.assento)
		npc.assento = null


func remover(npc: Node) -> void:
	if is_instance_valid(npc):
		npc.queue_free()


# ------------------------------------------------------------------ população

func _recalcular_alvos() -> void:
	var i := densidade - 1
	alvo_caminhantes = roundi(CAMINHANTES_POR_1000PX[i] * _largura_px / 1000.0)
	alvo_sentados = roundi(_assentos.size() * FRACAO_ASSENTOS[i])
	var excesso := alvo_caminhantes + alvo_sentados - maximo_de_npcs
	if excesso > 0:
		alvo_caminhantes = maxi(0, alvo_caminhantes - excesso)


func _ao_mudar_densidade() -> void:
	_recalcular_alvos()
	print("[Passageiros] densidade %d -> %d sentados + %d andando" % [densidade, alvo_sentados, alvo_caminhantes])
	densidade_mudou.emit(densidade)
	_mostrar_hud()


func _povoar_inicial() -> void:
	# sentados já nos lugares
	var livres := _assentos.duplicate()
	livres.shuffle()
	for i in mini(alvo_sentados, livres.size()):
		var a: Assento = livres[i]
		var npc := _criar_npc(_lista_livres[0])
		if npc == null:
			break
		a.ocupante = npc
		_reservados += 1
		npc.iniciar_sentado(a)
	# andando por aí, longe do jogador
	for i in alvo_caminhantes:
		_spawn_caminhante(true)
	_mostrar_hud()


func _process(delta: float) -> void:
	if not _pronto:
		return
	_acum += delta
	if _acum >= 0.5:
		_acum = 0.0
		_manter_populacao()
	if _debug_assentos or _debug_grade:
		queue_redraw()


func _manter_populacao() -> void:
	var alvo := alvo_sentados + alvo_caminhantes
	var n := _npcs.size()
	if n < alvo:
		_excesso_t = 0.0
		for i in mini(alvo - n, 3):
			_spawn_caminhante(false)
	elif n > alvo:
		_excesso_t += 0.5
		_remover_excedente(mini(n - alvo, 2))
	else:
		_excesso_t = 0.0


func _spawn_caminhante(inicial: bool) -> void:
	if _lista_livres.is_empty():
		return
	var rect := _retangulo_visivel(128.0)
	var celula := Vector2i.ZERO
	var achou := false
	for tentativa in 40:
		celula = _lista_livres[randi() % _lista_livres.size()]
		if ocupado.has(celula):
			continue
		var p := celula_global(celula)
		if inicial:
			if jogador == null or p.distance_to(jogador.global_position) > 250.0:
				achou = true
				break
		elif not rect.has_point(p):
			achou = true
			break
	if not achou:
		return # sem lugar fora da tela agora; tenta no próximo ciclo
	var npc := _criar_npc(celula)
	if npc != null:
		npc.iniciar_andando(randf_range(0.0, 2.5))


func _criar_npc(celula: Vector2i) -> Node:
	var npc := NpcScene.instantiate()
	get_parent().add_child(npc) # irmão do Player: o y-sort do Mundo cuida da ordem de desenho
	npc.global_position = celula_global(celula)
	var textura: Texture2D
	if texturas_npc.is_empty():
		textura = load(NpcScript.TEXTURA_PADRAO)
	else:
		textura = texturas_npc[randi() % texturas_npc.size()]
	npc.configurar(self, textura, randf(), randf_range(0.8, 1.15), celula)
	_npcs.append(npc)
	return npc


func _remover_excedente(quantos: int) -> void:
	var rect := _retangulo_visivel(96.0)
	var removidos := 0
	# primeiro: quem anda e está fora da tela
	for npc in _npcs.duplicate():
		if removidos >= quantos:
			break
		if npc.removendo or npc.esta_sentado():
			continue
		if not rect.has_point(npc.global_position):
			npc.removendo = true
			npc.queue_free()
			removidos += 1
	# se todos estão à vista há um tempo, some com o mais distante em fade
	if removidos == 0 and _excesso_t >= 6.0:
		var pior: Node = null
		var pior_d := -1.0
		for npc in _npcs:
			if npc.removendo or npc.esta_sentado():
				continue
			var d: float = npc.global_position.distance_to(jogador.global_position) if jogador else 0.0
			if d > pior_d:
				pior_d = d
				pior = npc
		if pior != null:
			pior.desvanecer()
			_excesso_t = 0.0


func _retangulo_visivel(margem: float) -> Rect2:
	var vp := get_viewport()
	var r: Rect2 = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	return r.grow(margem)


# ------------------------------------------------------------------ HUD / atalhos / debug

func _unhandled_key_input(event: InputEvent) -> void:
	if not teclas_de_atalho or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_PAGEUP:
			densidade += 1
			_mostrar_hud()
		KEY_PAGEDOWN:
			densidade -= 1
			_mostrar_hud()
		KEY_F3:
			_debug_assentos = not _debug_assentos
			queue_redraw()
		KEY_F4:
			_debug_grade = not _debug_grade
			queue_redraw()


func _criar_hud() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 50
	add_child(camada)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.modulate.a = 0.0
	camada.add_child(_hud)


func _mostrar_hud() -> void:
	if not mostrar_hud or _hud == null:
		return
	_hud.text = "Fluxo de passageiros: %d/10   (%d no aeroporto)\nPgUp/PgDn muda  •  F3 assentos  •  F4 grade" % [densidade, _npcs.size()]
	if _hud_tween:
		_hud_tween.kill()
	_hud.modulate.a = 1.0
	_hud_tween = create_tween()
	_hud_tween.tween_interval(2.5)
	_hud_tween.tween_property(_hud, "modulate:a", 0.0, 0.6)


func _draw() -> void:
	if not _pronto:
		return
	if _debug_grade:
		for c in _lista_livres:
			var p := to_local(celula_global(c))
			draw_rect(Rect2(p - _tam * 0.5 + Vector2.ONE, _tam - Vector2(2, 2)), Color(0.2, 0.6, 1.0, 0.18))
	if _debug_assentos:
		for a in _assentos:
			var cor := Color(1, 0.2, 0.2, 0.9) if a.ocupante != null else Color(0.2, 1, 0.3, 0.9)
			var p := to_local(a.pos)
			draw_circle(p, 6.0, cor)
			draw_line(to_local(a.centro), to_local(celula_global(a.acesso)), cor, 2.0)
