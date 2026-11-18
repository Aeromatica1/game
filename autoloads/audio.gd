extends Node
## Autoload "Audio": tudo de som do jogo num lugar só.
##
## - Clique de botão: QUALQUER BaseButton que entrar na árvore (inclusive os criados por código,
##   como as alternativas das questões) ganha o som automaticamente. Não precisa ligar botão a botão.
## - Música de fundo: existe UM único AudioStreamPlayer de música. Pedir uma faixa troca a que está
##   tocando (fade curto), então duas músicas nunca tocam juntas, mesmo trocando de cena rápido
##   (ex.: botão Voltar do mapa). Pedir a faixa que já está tocando não reinicia nada.
## - Volumes: barramentos "Musica" e "Som" (ajustados pelo menu de Opções e salvos em user://).
##
## Uso nas cenas:  Audio.tocar_menu()  /  Audio.tocar_aeroporto()

const BUS_MUSICA := "Musica"
const BUS_SOM := "Som"

# Referências por UID (continuam valendo se os arquivos forem renomeados ou movidos):
#   uid://b7yxfi1ghvc2k  assets/sounds/button.mp3
#   uid://bsl04vgs0xx42  assets/sounds/Mozart_ Overture - 'Le nozze di Figaro' ... .mp3
#   uid://cmmhu7iflwa71  assets/sounds/Violin Concerto No. 1 in A Minor, BWV 1041 ... .mp3
const SOM_BOTAO: AudioStream = preload("uid://b7yxfi1ghvc2k")
const MUSICA_MENU: AudioStream = preload("uid://bsl04vgs0xx42")
const MUSICA_AEROPORTO: AudioStream = preload("uid://cmmhu7iflwa71")

const ARQUIVO_CONFIG := "user://configuracoes.cfg"
const VOLUME_SILENCIO := -40.0      # dB: "mudo" do fade (o volume real vem do barramento)
const FADE_SAIDA := 0.35            # s
const FADE_ENTRADA := 0.6           # s

var _musica: AudioStreamPlayer
var _cliques: AudioStreamPlayer
var _atual: AudioStream = null      # faixa PEDIDA mais recente (null = nenhuma)
var _tween: Tween
var _volumes := {BUS_MUSICA: 70.0, BUS_SOM: 70.0}     # 0..100
var _salvar_agendado := false


func _ready() -> void:
	# Música e cliques continuam com o jogo pausado (Opções, questões, minigames pausam a árvore).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_garantir_bus(BUS_MUSICA)
	_garantir_bus(BUS_SOM)
	_carregar_config()
	for bus: String in _volumes:
		_aplicar_volume(bus)

	_ativar_loop(MUSICA_MENU)
	_ativar_loop(MUSICA_AEROPORTO)

	_musica = AudioStreamPlayer.new()
	_musica.name = "Musica"
	_musica.bus = BUS_MUSICA
	_musica.finished.connect(_ao_terminar_musica)
	add_child(_musica)

	_cliques = AudioStreamPlayer.new()
	_cliques.name = "Cliques"
	_cliques.bus = BUS_SOM
	_cliques.stream = SOM_BOTAO
	_cliques.max_polyphony = 8       # cliques rápidos (ex.: campo minado) não se cortam
	add_child(_cliques)

	# Todo botão que entrar na árvore a partir de agora (e os que já existirem) toca o som.
	get_tree().node_added.connect(_ao_entrar_na_arvore)
	_ligar_existentes(get_tree().root)


func _exit_tree() -> void:
	if _salvar_agendado:
		_salvar_config()


# ==================== Cliques de botão ====================

func _ao_entrar_na_arvore(no: Node) -> void:
	if no is BaseButton:
		_ligar_botao(no as BaseButton)


func _ligar_existentes(no: Node) -> void:
	if no is BaseButton:
		_ligar_botao(no as BaseButton)
	for filho in no.get_children():
		_ligar_existentes(filho)


func _ligar_botao(botao: BaseButton) -> void:
	# `pressed` só dispara em botão habilitado, por clique, Enter ou Espaço.
	if not botao.pressed.is_connected(tocar_botao):
		botao.pressed.connect(tocar_botao)


## Toca o som de clique (também pode ser chamado direto de qualquer script).
func tocar_botao() -> void:
	_cliques.play()


# ==================== Música ====================

func tocar_menu() -> void:
	tocar_musica(MUSICA_MENU)


func tocar_aeroporto() -> void:
	tocar_musica(MUSICA_AEROPORTO)


## Toca `faixa` em loop. Se outra estiver tocando, ela some com um fade antes da nova entrar
## (nunca as duas juntas). Se `faixa` já é a atual, não faz nada (não reinicia).
func tocar_musica(faixa: AudioStream) -> void:
	if faixa == null or faixa == _atual:
		return
	_atual = faixa
	_parar_tween()
	if _musica.playing and _musica.stream != faixa:
		_tween = create_tween()
		_tween.tween_property(_musica, "volume_db", VOLUME_SILENCIO, FADE_SAIDA)
		_tween.tween_callback(_iniciar.bind(faixa))
	else:
		_iniciar(faixa)


## Para a música com fade.
func parar_musica() -> void:
	_atual = null
	_parar_tween()
	if not _musica.playing:
		return
	_tween = create_tween()
	_tween.tween_property(_musica, "volume_db", VOLUME_SILENCIO, FADE_SAIDA)
	_tween.tween_callback(_musica.stop)


func _iniciar(faixa: AudioStream) -> void:
	# Mesma faixa ainda tocando (pedido de volta no meio do fade-out): só sobe o volume de novo.
	if _musica.stream != faixa or not _musica.playing:
		_musica.stream = faixa
		_musica.volume_db = VOLUME_SILENCIO
		_musica.play()
	_tween = create_tween()
	_tween.tween_property(_musica, "volume_db", 0.0, FADE_ENTRADA)


func _parar_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## Rede de segurança caso o loop do stream não esteja ativo.
func _ao_terminar_musica() -> void:
	if _atual != null and _musica.stream == _atual:
		_musica.play()


func _ativar_loop(stream: AudioStream) -> void:
	if "loop" in stream:                # AudioStreamMP3 / AudioStreamOggVorbis
		stream.set("loop", true)


# ==================== Volumes (menu de Opções) ====================

## Volume atual do barramento, de 0 a 100.
func volume(bus: String) -> float:
	return float(_volumes.get(bus, 100.0))


## Aplica na hora e salva (agrupando vários movimentos do slider numa única gravação).
func definir_volume(bus: String, percentual: float) -> void:
	if not _volumes.has(bus):
		return
	_volumes[bus] = clampf(percentual, 0.0, 100.0)
	_aplicar_volume(bus)
	_agendar_salvar()


func _aplicar_volume(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	var p: float = _volumes[bus]
	AudioServer.set_bus_mute(i, p <= 0.0)
	if p > 0.0:
		AudioServer.set_bus_volume_db(i, linear_to_db(p / 100.0))


## Se o default_bus_layout.tres não existir/não tiver o barramento, cria em tempo de execução.
func _garantir_bus(nome: String) -> void:
	if AudioServer.get_bus_index(nome) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, nome)
	AudioServer.set_bus_send(i, "Master")


func _carregar_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ARQUIVO_CONFIG) != OK:
		return
	for bus: String in _volumes:
		_volumes[bus] = clampf(float(cfg.get_value("audio", bus.to_lower(), _volumes[bus])), 0.0, 100.0)


func _salvar_config() -> void:
	_salvar_agendado = false
	var cfg := ConfigFile.new()
	cfg.load(ARQUIVO_CONFIG)            # preserva outras seções, se existirem
	for bus: String in _volumes:
		cfg.set_value("audio", bus.to_lower(), _volumes[bus])
	cfg.save(ARQUIVO_CONFIG)


func _agendar_salvar() -> void:
	if _salvar_agendado:
		return
	_salvar_agendado = true
	await get_tree().create_timer(0.5).timeout
	if _salvar_agendado:
		_salvar_config()
