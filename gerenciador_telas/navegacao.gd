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

const CENA_TELAS := "res://gerenciador_telas/gerenciador_telas.tscn"
const CENA_MAPA := "res://mapa/mapa.tscn"

var _historico: Array[String] = []
var _pendente := false


## Guarda o histórico atual das telas e abre o mapa.
func ir_para_mapa(historico_telas: Array[String]) -> void:
	_historico = historico_telas.duplicate()
	_pendente = true
	get_tree().change_scene_to_file(CENA_MAPA)


## Volta do mapa para a tela anterior do histórico (a última, normalmente SaveSlot).
func voltar_do_mapa() -> void:
	get_tree().change_scene_to_file(CENA_TELAS)


## Entrega (uma única vez) o histórico guardado; vazio se não houver.
func consumir_historico() -> Array[String]:
	if not _pendente:
		return []
	_pendente = false
	return _historico.duplicate()
