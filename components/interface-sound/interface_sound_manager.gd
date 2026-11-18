class_name InterfaceSoundManager
extends Node
## Gerenciador dos efeitos sonoros de interface — a ÚNICA fonte de
## reprodução dos cliques de UI (`pluck_002`) e da seleção de fase
## (`select_002`).
##
## Por que Autoload (ver `project.godot`, `InterfaceSounds`): o som do
## clique é disparado IMEDIATAMENTE ANTES de `change_scene_to_file` —
## se o reprodutor morasse na cena antiga, ele seria liberado junto e o
## clique seria cortado. Autoloads são filhos do root e sobrevivem à
## troca de cena, então o clique continua tocando na cena nova — mesmo
## padrão de persistência do BackgroundMusicManager.
##
## Regras de uso (pedido da feature):
##  - todo botão de interface reproduz `pluck_002` ao ser acionado;
##  - EXCEÇÕES: botão de disparo (fire_button) e seletor de força
##    (power_slider) NÃO reproduzem som — por isso esses dois scripts
##    nunca chamam este gerenciador;
##  - clicar numa fase na tela Levels (desbloqueada ou bloqueada)
##    reproduz `select_002` (em vez do pluck).
##
## Mixagem: pool fixo de MAX_VOICES AudioStreamPlayers (filhos deste nó,
## nunca criados por clique), com round-robin — cliques rápidos nunca
## se cortam nem estouram o número de vozes. Volume único centralizado
## (VOLUME_DB). Processo ALWAYS: popups de pause rodam com a árvore
## pausada e o clique precisa tocar mesmo assim (mesmo motivo do
## BackgroundMusicManager).

## Clique genérico de botão.
const PLUCK_STREAM: AudioStreamOggVorbis = preload("res://assets/audio/interface/pluck_002.ogg")
## Seleção de fase na tela Levels.
const SELECT_STREAM: AudioStreamOggVorbis = preload("res://assets/audio/interface/select_002.ogg")

## Volume dos cliques (dB). Trilha em -6 dB e impactos em +15 dB: 0 dB
## deixa o clique presente sem competir com os impactos.
const VOLUME_DB := 0.0

## Pool de vozes = limite rígido de cliques simultâneos. Cliques de UI
## são isolados (sem rajadas como nos impactos): 4 cobre spam de botão
## sem cortar o anterior.
const MAX_VOICES := 4

## Instância ativa publicada (espelho de BackgroundMusicManager.current
## e ImpactSoundManager.current). Limpa em _exit_tree. Os chamadores
## usam os atalhos estáticos `pluck()`/`select_sound()`, que são no-op
## seguros sem gerenciador na cena (tests/guides).
static var current: InterfaceSoundManager

var _voices: Array[AudioStreamPlayer] = []
var _next := 0

## Ganho do nível de SFX (0.0..1.0) vindo das configurações
## (SettingsManager). Multiplica o trim VOLUME_DB sem alterá-lo.
var _sfx_level := 1.0


func _ready() -> void:
	if is_instance_valid(current) and current != self:
		queue_free()
		return
	current = self
	# Configurações aplicadas ANTES de qualquer clique: o jogo nunca
	# toca temporariamente com o volume errado no boot.
	_sfx_level = clampf(float(SettingsManager.get_sfx_volume()) / 100.0, 0.0, 1.0)
	# O clique precisa tocar com a árvore pausada (popup de pause) e
	# atravessar a troca de cena (Autoload já sobrevive; o modo ALWAYS
	# garante que o player não seja pausado junto).
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % (i + 1)
		voice.volume_db = VOLUME_DB + SettingsManager.level_to_db_gain(_sfx_level)
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		_voices.append(voice)


func _exit_tree() -> void:
	if current == self:
		current = null


## Atalho estático seguro (no-op sem gerenciador): clique genérico.
static func pluck() -> void:
	if current != null:
		current.play_pluck()


## Atalho estático seguro (no-op sem gerenciador): seleção de fase.
static func select_sound() -> void:
	if current != null:
		current.play_select()


## Reproduz o clique genérico de botão.
func play_pluck() -> void:
	_play(PLUCK_STREAM)


## Reproduz o som de seleção de fase (tela Levels).
func play_select() -> void:
	_play(SELECT_STREAM)


func _play(stream: AudioStream) -> void:
	if _voices.is_empty() or stream == null:
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = VOLUME_DB + SettingsManager.level_to_db_gain(_sfx_level)
	voice.play()


## Aplica o nível de SFX (0.0..1.0) das configurações: ganho somado ao
## trim VOLUME_DB, sem alterá-lo. Vale para todas as vozes futuras; as
## vozes ociosas já nascem com o nível atual.
func set_sfx_level(level01: float) -> void:
	_sfx_level = clampf(level01, 0.0, 1.0)
	for voice in _voices:
		if not voice.playing:
			voice.volume_db = VOLUME_DB + SettingsManager.level_to_db_gain(_sfx_level)
