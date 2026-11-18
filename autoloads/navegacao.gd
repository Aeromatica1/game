extends Node
## Autoload "Navegacao": ponte entre o GerenciadorTelas e o Mapa.
##
## O mapa é uma cena separada (change_scene_to_file), então o GerenciadorTelas é
## destruído ao entrar nele e o histórico de telas se perderia. Aqui guardamos o
## histórico como NOMES de nós (não referências, que morrem junto com a cena) e o
## GerenciadorTelas o reconstrói ao ser recriado.
##
## Ida:    GerenciadorTelas -> ir_para_mapa(nomes_do_historico)
## Volta:  Mapa             -> voltar_do_mapa()  (GerenciadorTelas chama consumir_historico())

const CENA_TELAS := "res://telas/gerenciador_telas/gerenciador_telas.tscn"
const CENA_MAPA := "res://aeroporto/mapa/mapa.tscn"

var _historico: Array[String] = []
var _mapa_pedido := false
var _pendente := false


## Começa a carregar o mapa em segundo plano (disco + parse do .tscn grande). Chame quando
## o jogador chegar na tela de saves: ao escolher o slot a cena já estará pronta.
func pre_carregar_mapa() -> void:
	if _mapa_pedido:
		return
	_mapa_pedido = ResourceLoader.load_threaded_request(CENA_MAPA) == OK


## Guarda o histórico atual das telas e abre o mapa.
func ir_para_mapa(historico_telas: Array[String]) -> void:
	pre_carregar_mapa()          # carrega em segundo plano enquanto a tela escurece
	Transicao.executar(_abrir_mapa.bind(historico_telas.duplicate()))


func _abrir_mapa(historico_telas: Array[String]) -> void:
	_historico = historico_telas
	_pendente = true
	var cena: PackedScene = null
	if _mapa_pedido:
		cena = ResourceLoader.load_threaded_get(CENA_MAPA) as PackedScene
		_mapa_pedido = false          # o pedido foi consumido; o próximo precisa de novo request
	if cena != null:
		get_tree().change_scene_to_packed(cena)
	else:
		get_tree().change_scene_to_file(CENA_MAPA)


## Volta ao menu principal (sem restaurar o histórico de telas).
## `antes_da_troca` (opcional) roda com a tela já escura, logo antes de trocar a cena.
func voltar_ao_menu(antes_da_troca: Callable = Callable()) -> void:
	Transicao.executar(func() -> void:
		if antes_da_troca.is_valid():
			antes_da_troca.call()
		_historico = []
		_pendente = false
		get_tree().change_scene_to_file(CENA_TELAS))


## Volta do mapa para a tela anterior do histórico (a última, normalmente SaveSlot).
func voltar_do_mapa() -> void:
	Transicao.executar(func() -> void: get_tree().change_scene_to_file(CENA_TELAS))


## Entrega (uma única vez) o histórico guardado; vazio se não houver.
func consumir_historico() -> Array[String]:
	if not _pendente:
		return []
	_pendente = false
	return _historico.duplicate()
