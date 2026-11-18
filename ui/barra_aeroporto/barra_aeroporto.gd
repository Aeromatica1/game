extends CanvasLayer
## Script da BarraAeroporto (raiz de ui/barra_aeroporto/barra_aeroporto.tscn).
## Recebe o resumo do aeroporto de mapa.gd (`atualizar`) e escreve nos Labels.
##
## Layout: Voltar, Nível, Tarefas, Erradas, Alugados, Dinheiro e Menu ficam numa única HBox
## com espaçadores de mesmo peso entre eles -> lacunas iguais de ponta a ponta da barra.

signal voltar_solicitado
signal menu_solicitado

@onready var nivel_label: Label = $Margem/Itens/NivelLabel
@onready var tarefas_label: Label = $Margem/Itens/Tarefa/TarefasLabel
@onready var erradas_label: Label = $Margem/Itens/Erradas/ErradasLabel
@onready var alugados_label: Label = $Margem/Itens/Alugados/AlugadosLabel
@onready var dinheiro_label: Label = $Margem/Itens/Dinheiro/DinheiroLabel
@onready var voltar_botao: Button = $Margem/Itens/Voltar
@onready var menu_botao: Button = $Margem/Itens/Menu

# Itens escondidos enquanto um menu (Opções/Ajuda) está aberto, para não poluir o título da tela.
@onready var _estatisticas: Array = [
	nivel_label, $Margem/Itens/Tarefa, $Margem/Itens/Erradas,
	$Margem/Itens/Alugados, $Margem/Itens/Dinheiro]


func _ready() -> void:
	voltar_botao.pressed.connect(voltar_solicitado.emit)
	menu_botao.pressed.connect(menu_solicitado.emit)


## Esconde/mostra os contadores (o mapa chama com true ao abrir Opções/Ajuda).
func modo_menu(aberto: bool) -> void:
	for c: Control in _estatisticas:
		c.visible = not aberto


func atualizar(d: Dictionary) -> void:
	var nome: String = d.get("nivel_nome", "")
	nivel_label.text = "Nível %d%s" % [d.get("nivel", 1), (" - " + nome) if nome != "" else ""]
	dinheiro_label.text = _numero(float(d.get("dinheiro", 0.0)))

	# Meta = questões necessárias para evoluir (as mesmas do limite de erros do game over).
	# No último nível não há próximo: usa o total de questões do nível.
	var prox: Dictionary = d.get("proximo_nivel", {})
	var meta := int(prox.get("questoes_necessarias", d.get("questoes_do_nivel", 0)))
	tarefas_label.text = "%d/%d" % [mini(int(d.get("questoes_acertadas", 0)), meta), meta]
	erradas_label.text = "%d/%d" % [int(d.get("erradas", 0)), meta]
	alugados_label.text = "%d/%d" % [int(d.get("alugueis", 0)), int(d.get("alugueis_total", 27))]


## 1234567.5 -> "1.234.567,50" (casas = 2 por padrão).
static func _numero(v: float, casas: int = 2) -> String:
	var s := String.num(absf(v), casas)
	var partes := s.split(".")
	var inteiro := partes[0]
	var out := ""
	while inteiro.length() > 3:
		out = "." + inteiro.substr(inteiro.length() - 3) + out
		inteiro = inteiro.substr(0, inteiro.length() - 3)
	out = inteiro + out
	if partes.size() > 1:
		out += "," + partes[1]
	return ("-" if v < 0.0 else "") + out
