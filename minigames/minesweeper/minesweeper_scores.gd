extends RefCounted
## Recordes (melhores tempos) do Campo Minado.
##
## Guarda os MAX_ENTRIES melhores tempos de cada dificuldade em
## user://minesweeper_scores.json. Os dados ficam num formato simples e
## versionado (to_dict / from_dict), pensado para ser embutido depois no
## sistema de saves da conta ou enviado a um ranking validado pelo servidor.
##
## Uso:
##   const Scores = preload("res://minigames/minesweeper/minesweeper_scores.gd")
##   var scores := Scores.new()
##   var result := scores.submit("beginner", 23450)   # tempo em milissegundos
##   scores.best_ms("beginner")

const SAVE_PATH := "user://minesweeper_scores.json"
const FORMAT_VERSION := 1
const MAX_ENTRIES := 5

## dificuldade -> Array de {"time_ms": int, "date": "AAAA-MM-DD"}, do melhor para o pior
var _levels: Dictionary = {}

## preferências do minigame que também vale a pena persistir
var settings: Dictionary = {"marks": false}


func _init() -> void:
	load_from_disk()


## Melhor tempo da dificuldade em ms, ou 0 se ainda não existe.
func best_ms(level: String) -> int:
	var list := top(level)
	if list.is_empty():
		return 0
	return int(list[0]["time_ms"])


## Lista dos melhores tempos da dificuldade (do menor para o maior).
func top(level: String) -> Array:
	var list: Array = _levels.get(level, [])
	return list


## Registra uma vitória. Retorna:
##   {"new_record": bool,  # bateu o melhor tempo (ou é o primeiro)
##    "rank": int}         # posição no top (1 = melhor); 0 se não entrou no top
func submit(level: String, time_ms: int) -> Dictionary:
	var previous_best := best_ms(level)
	var list: Array = _levels.get(level, [])
	var entry := {"time_ms": time_ms, "date": Time.get_date_string_from_system()}

	list.append(entry)
	_sort_entries(list)
	var rank := list.find(entry) + 1
	if list.size() > MAX_ENTRIES:
		list.resize(MAX_ENTRIES)
	_levels[level] = list

	var made_top := rank >= 1 and rank <= MAX_ENTRIES
	if made_top:
		save_to_disk()
	return {
		"new_record": made_top and (previous_best == 0 or time_ms < previous_best),
		"rank": rank if made_top else 0,
	}


## Apaga todos os recordes (as preferências são mantidas).
func reset() -> void:
	_levels.clear()
	save_to_disk()


func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"levels": _levels,
		"settings": settings,
	}


## Carrega de um dicionário, descartando qualquer entrada inválida.
func from_dict(data: Dictionary) -> void:
	_levels.clear()

	var raw_levels: Variant = data.get("levels", {})
	if typeof(raw_levels) == TYPE_DICTIONARY:
		for key in raw_levels:
			var raw_list: Variant = raw_levels[key]
			if typeof(raw_list) != TYPE_ARRAY:
				continue
			var clean: Array = []
			for item in raw_list:
				if typeof(item) != TYPE_DICTIONARY or not item.has("time_ms"):
					continue
				var t := int(item["time_ms"])
				if t > 0:
					clean.append({"time_ms": t, "date": str(item.get("date", ""))})
			_sort_entries(clean)
			if clean.size() > MAX_ENTRIES:
				clean.resize(MAX_ENTRIES)
			_levels[str(key)] = clean

	var raw_settings: Variant = data.get("settings", {})
	if typeof(raw_settings) == TYPE_DICTIONARY:
		settings["marks"] = bool(raw_settings.get("marks", false))


func save_to_disk() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Minesweeper: não foi possível salvar os recordes (%s)." % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()

	# arquivo corrompido: começa do zero em vez de quebrar o jogo
	var json := JSON.new()
	if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
		from_dict(json.data)


func _sort_entries(list: Array) -> void:
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["time_ms"]) < int(b["time_ms"]))
