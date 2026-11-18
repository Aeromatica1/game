extends Control
## Menu de Opções: volume da Música e volume do Som (cliques).
## Os valores moram no autoload Audio, que aplica nos barramentos e salva em user://.
## Funciona igual no gerenciador de telas e por cima do mapa (com o jogo pausado).

@onready var musica_slider: HSlider = $OpcoesArea/VBoxContainer/MusicaArea/MusicaSlider
@onready var musica_valor: Label = $OpcoesArea/VBoxContainer/MusicaArea/MusicaValor
@onready var som_slider: HSlider = $OpcoesArea/VBoxContainer/SomArea/SomSlider
@onready var som_valor: Label = $OpcoesArea/VBoxContainer/SomArea/SomValor


func _ready() -> void:
	_ligar(musica_slider, musica_valor, Audio.BUS_MUSICA)
	_ligar(som_slider, som_valor, Audio.BUS_SOM)

	# Ao soltar o slider do Som, toca um clique no volume novo para a pessoa ouvir o resultado.
	som_slider.drag_ended.connect(func(_mudou: bool) -> void: Audio.tocar_botao())

	# Sempre que a tela reaparecer, mostra os valores reais (e não os do .tscn).
	visibility_changed.connect(_sincronizar)
	_sincronizar()


func _ligar(slider: HSlider, rotulo: Label, bus: String) -> void:
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value_changed.connect(func(v: float) -> void:
		rotulo.text = "%d%%" % int(v)
		Audio.definir_volume(bus, v))


func _sincronizar() -> void:
	_mostrar(musica_slider, musica_valor, Audio.BUS_MUSICA)
	_mostrar(som_slider, som_valor, Audio.BUS_SOM)


func _mostrar(slider: HSlider, rotulo: Label, bus: String) -> void:
	slider.set_value_no_signal(Audio.volume(bus))
	rotulo.text = "%d%%" % int(slider.value)
