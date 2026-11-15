class_name BackgroundMusicManager
extends Node
## Gerenciador da música de fundo contínua — a ÚNICA fonte da trilha,
## registrado como Autoload no project.godot (`BackgroundMusic`).
##
## Por que Autoload: os autoloads são filhos diretos do root e NÃO são
## destruídos por `SceneTree.change_scene_to_file` (só o `current_scene`
## é trocado). A música nasce uma única vez no boot do jogo e atravessa
## home → Levels → partida → popups de vitória/derrota → menus sem
## reiniciar, sem criar novos reprodutores e sem sobrepor instâncias —
## exatamente o requisito de continuidade entre cenas. Nenhuma troca de
## cena, `load_level` (retry/next) ou popup toca neste nó: o `_ready` do
## Autoload roda uma única vez por execução.
##
## Reprodutor único: UM AudioStreamPlayer criado em `_ready` (mesmo
## padrão de criação em código do ImpactSoundManager — nenhum nó de
## áudio é instanciado por cena ou transição; o player morre junto com
## o gerenciador, nunca vira órfão).
##
## Loop: `loop = true` aplicado em runtime sobre o stream pré-carregado
## (`preload` carrega o recurso uma única vez, no carregamento do
## script). O arquivo .mp3 original NÃO é modificado — apenas a
## instância em memória recebe a propriedade.
##
## Mixagem: bus dedicado "Music" (default_bus_layout.tres → Master,
## 0 dB), separado do Master onde os SFX tocam (SFX_VOLUME_DB e os
## trims por material do ImpactSoundManager permanecem intocados). O
## trim de fundo fica no próprio player (VOLUME_DB): a música mede
## média -14,3 dB / pico 0 dB (ffmpeg volumedetect) e os SFX são
## amplificados +15 dB sobre médias ~-22 dB — com -12 dB a trilha
## fica ~19 dB abaixo da média dos impactos: presente como fundo,
## sem competir com os efeitos.
##
## Instância duplicada: `current` publicado no estático (espelho do
## ImpactSoundManager.current) + descarte em `_ready` — uma segunda
## instância (ex.: teste mal registrado) se libera antes de criar outro
## reprodutor, impedindo sobreposição mesmo fora do caminho do Autoload.
## `current` é limpo em `_exit_tree` (nenhum ponteiro morto).

## Bus dedicado da música (ver default_bus_layout.tres). Os SFX seguem
## no Master — mixagem independente nos dois sentidos.
const MUSIC_BUS := "Music"

## Volume de fundo (dB) aplicado no player. Racional no doc da classe:
## -12 dB sobre a música (média -14,3 dB) mantém a trilha ~19 dB
## abaixo dos SFX amplificados +15 dB — audível como fundo, nunca
## competindo com os efeitos.
const VOLUME_DB := -12.0

## Stream da música (asset original; `loop` é configuração em memória).
const MUSIC_STREAM: AudioStreamMP3 = preload("res://assets/audio/Glass_Horizon.mp3")

## Instância ativa publicada para os produtores/testes (padrão
## ImpactSoundManager.current). Limpa em _exit_tree.
static var current: BackgroundMusicManager

## Único reprodutor da trilha (filho deste nó — morre junto com ele).
var _player: AudioStreamPlayer


func _ready() -> void:
	if is_instance_valid(current) and current != self:
		# Instância duplicada: descarta SEM tocar (no jogo real o
		# Autoload garante uma única; testes podem criar extras).
		queue_free()
		return
	current = self
	_ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.bus = MUSIC_BUS
	_player.volume_db = VOLUME_DB
	# Loop em runtime: não altera o .mp3 original, só a instância em
	# memória (compartilhada via preload — configurada uma única vez).
	# O alias local contorna a imutabilidade de membros de `const`
	# imposta pelo GDScript; o recurso em si é mutável em runtime.
	var stream: AudioStreamMP3 = MUSIC_STREAM
	stream.loop = true
	_player.stream = stream
	add_child(_player)
	# A trilha não pode pausar junto com a árvore (popup de pause usa
	# get_tree().paused): com PROCESS_MODE_ALWAYS o player continua
	# tocando e retoma do mesmo ponto — sem silêncio, sem reinício.
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	# Idempotente: só inicia se ainda não estiver tocando.
	if not _player.playing:
		_player.play()


func _exit_tree() -> void:
	if current == self:
		current = null


## Garante o bus "Music" mesmo sem o default_bus_layout.tres (fallback
## defensivo: sem o bus o player cairia no Master e misturaria com os
## SFX). Com o layout presente é no-op.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(idx, MUSIC_BUS)
	AudioServer.set_bus_send(idx, "Master")
