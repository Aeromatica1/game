extends Control

const BUS_MUSICA := "Musica"
const BUS_SOM := "Som"

@onready var musica_slider: HSlider = $OpcoesArea/VBoxContainer/MusicaArea/MusicaSlider
@onready var musica_valor: Label = $OpcoesArea/VBoxContainer/MusicaArea/MusicaValor
@onready var som_slider: HSlider = $OpcoesArea/VBoxContainer/SomArea/SomSlider
@onready var som_valor: Label = $OpcoesArea/VBoxContainer/SomArea/SomValor


func _ready() -> void:
	_ligar(musica_slider, musica_valor, BUS_MUSICA)
	_ligar(som_slider, som_valor, BUS_SOM)


func _ligar(slider: HSlider, rotulo: Label, bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx != -1:
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(idx)) * 100.0

	var atualizar := func(v: float) -> void:
		rotulo.text = "%d%%" % int(v)
		var i := AudioServer.get_bus_index(bus)
		if i != -1:
			AudioServer.set_bus_mute(i, v <= 0.0)
			if v > 0.0:
				AudioServer.set_bus_volume_db(i, linear_to_db(v / 100.0))

	slider.value_changed.connect(atualizar)
	atualizar.call(slider.value)
