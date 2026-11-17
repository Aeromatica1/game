extends Node
## Script da BarraAeroporto (anexe à raiz de hud/barra_aeroporto.tscn).
## Recebe o resumo do aeroporto de mapa.gd (`atualizar`) e escreve nos Labels.
## Os campos são opcionais: arraste, no Inspetor, cada Label já existente na barra
## para o export correspondente; os que ficarem vazios são ignorados.

signal voltar_solicitado

@onready var nivel_label: Label = $NivelLabel
@onready var dinheiro_label: Label = $DinheiroLabel
@onready var tarefas_label: Label = $TarefasLabel

## Opcional: se definido, o clique emite `voltar_solicitado` (o mapa volta às telas).
@onready var voltar_botao: Button = $Voltar
@onready var conta: Button = $Conta

func _ready() -> void:
	if voltar_botao:
		voltar_botao.pressed.connect(voltar_solicitado.emit)


func atualizar(d: Dictionary) -> void:
	if nivel_label:
		var nome: String = d.get("nivel_nome", "")
		nivel_label.text = "Nível %d%s" % [d.get("nivel", 1), (" - " + nome) if nome != "" else ""]
	if dinheiro_label:
		dinheiro_label.text = _numero(float(d.get("dinheiro", 0.0)))
	if tarefas_label:
		tarefas_label.text = "%d/%d" % [d.get("questoes_acertadas", 0), d.get("questoes_do_nivel", 0)]
	"""
	if label_alugueis:
		label_alugueis.text = str(d.get("alugueis", 0))
	if label_fluxo:
		label_fluxo.text = _numero(float(d.get("fluxo_passageiros", 0.0)), 0)
	"""


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
