class_name ImpactSoundManager
extends Node
## Gerenciador centralizado dos efeitos sonoros de impacto — a ÚNICA
## fonte de reprodução (nenhuma bala/obstáculo controla áudio próprio).
## É espelho do padrão do ImpactTextManager: referência publicada no
## estático `current`, lida pelo roteador da Bullet, e limpa em
## `_exit_tree` (troca de cena não deixa ponteiro morto).
##
## Materiais → sons: cada material usa EXCLUSIVAMENTE os arquivos da
## pasta do próprio elemento (SOUNDS_BY_MATERIAL, com `preload` — os
## recursos são carregados uma única vez na carga do script, nunca
## durante uma colisão). Material fora do mapa cai no conjunto do chão
## (fallback seguro, mesmo critério do ImpactTextManager.texts_for).
##
## Variação anti-repetição:
##  - pools com >1 arquivo: sorteio SEM repetir o índice imediatamente
##    anterior (_pick_stream exclui o último índice e sorteia uniforme
##    entre os demais — cada arquivo tem a mesma probabilidade marginal,
##    distribuição equilibrada por construção);
##  - Glass (arquivo único): pitch aleatório dentro da faixa
##    [GLASS_PITCH_MIN, GLASS_PITCH_MAX], centralizada aqui.
##
## Precisão/sincronização: este nó NÃO decide QUANDO tocar — o roteador
## único da bala (`Bullet._route_hit` + contato do CCD) chama `play()`
## somente em impactos confirmados, com dedup por instância e por frame
## de física da bala. Ver bullet.gd/_play_impact_sound.
##
## Mixagem: pool fixo de MAX_VOICES AudioStreamPlayers (filhos deste nó —
## liberados junto da cena, sem nós órfãos). Impactos simultâneos
## compartilham vozes sem cortar uns aos outros; só na saturação do pool
## a voz mais antiga é reiniciada (roubo por menor tempo de uso), o que
## limita o número máximo de reproduções simultâneas. Volume por
## material (VOLUME_DB_BY_MATERIAL) compensa as diferenças medidas entre
## os arquivos; o trim é somado ao SFX_VOLUME_DB global.
##
## Fim de fase: game.gd/load_level chama `stop_all()` — nenhum som da
## fase anterior atravessa a troca. Sem gerenciador na cena
## (tests/guides), o roteador da bala é no-op.

## Material do chão/parede estática do cenário — mesma chave de
## ImpactTextManager (fonte única do kind, lida por Bullet._impact_material).
const KIND_FLOOR := ImpactTextManager.KIND_FLOOR

## Volume global dos SFX (dB), aplicado antes do trim por material.
## Picos dos arquivos ficam perto de -1 dB; -6 dB deixa margem para
## impactos simultâneos somarem sem saturar a saída.
const SFX_VOLUME_DB := -6.0

## Trim de volume por material (dB), somado ao SFX_VOLUME_DB. Calibrado
## sobre as medições dos arquivos (ffmpeg volumedetect): metal tem a
## média mais alta (~-20,6 dB), pedra e chão ~-22 dB, e o pico do vidro
## é 1,5 dB abaixo dos demais — o vidro é agudo e corta bem, por isso o
## ajuste é conservador. Material fora do mapa usa 0.0.
const VOLUME_DB_BY_MATERIAL: Dictionary = {
	ObstacleDefinition.KIND_GLASS: 2.0,
	ObstacleDefinition.KIND_STONE: 1.0,
	ObstacleDefinition.KIND_METAL: -1.0,
	KIND_FLOOR: 0.0,
}

## Faixa de pitch do Glass (arquivo único — sem variação de arquivo, o
## pitch carrega a diversidade). ±5% é perceptível o bastante para cada
## estilhaço soar distinto, sem descaracterizar o som de vidro nem
## sugerir outro material. Ajuste centralizado aqui.
const GLASS_PITCH_MIN := 0.95
const GLASS_PITCH_MAX := 1.05

## Micro-variação de pitch (±) para os materiais com múltiplos arquivos:
## os arquivos já variam entre si; um desvio pequeno quebra o timbre
## "idêntico" entre reproduções sem alterar a identidade do material.
const PITCH_JITTER := 0.025

## Offset inicial (segundos) por material ao chamar `AudioStreamPlayer.play()`.
## breakingGlass_000.ogg tem ~3,55 s de silêncio antes do estouro real
## (medição ffmpeg: silêncio < -57 dB até 3,5 s; transiente em 3,6 s;
## cauda audível até ~5 s; arquivo com 6,04 s no total). Reproduzir do
## início atrasaria o som em 3,5 s em relação ao impacto visual — o
## offset entra exatamente no ataque do vidro, com 50 ms de folga de
## silêncio inaudível. Demais materiais começam em 0.0 (arquivos já
## começam no transiente).
const START_OFFSET_BY_MATERIAL: Dictionary = {
	ObstacleDefinition.KIND_GLASS: 3.55,
}

## Tamanho do pool de vozes = limite rígido de reproduções simultâneas.
## 8 cobre rajadas (várias balas + junção) sem cortar sons anteriores;
## acima disso a voz mais antiga é reiniciada (impactos são curtos:
## 0,1–0,36 s; só o vidro demora ~2,5 s audíveis).
const MAX_VOICES := 8

## Mapeamento CENTRAL material → arquivos de áudio (assets já presentes
## no projeto; nenhum arquivo criado ou substituído). Chaves de obstáculo
## reutilizam ObstacleDefinition.KIND_* (fonte única dos materiais).
## Adicionar material novo = 1 entrada aqui (+ 1 ramo em
## `Bullet._impact_material()` para o roteador reconhecer o nó).
const SOUNDS_BY_MATERIAL: Dictionary = {
	ObstacleDefinition.KIND_STONE: [
		preload("res://assets/obstacles/stone/impactStone_medium_000.ogg"),
		preload("res://assets/obstacles/stone/impactStone_medium_001.ogg"),
		preload("res://assets/obstacles/stone/impactStone_medium_002.ogg"),
		preload("res://assets/obstacles/stone/impactStone_medium_003.ogg"),
		preload("res://assets/obstacles/stone/impactStone_medium_004.ogg"),
	],
	ObstacleDefinition.KIND_METAL: [
		preload("res://assets/obstacles/metal/impactMetal_heavy_000.ogg"),
		preload("res://assets/obstacles/metal/impactMetal_heavy_001.ogg"),
		preload("res://assets/obstacles/metal/impactMetal_heavy_002.ogg"),
		preload("res://assets/obstacles/metal/impactMetal_heavy_003.ogg"),
		preload("res://assets/obstacles/metal/impactMetal_heavy_004.ogg"),
	],
	ObstacleDefinition.KIND_GLASS: [
		preload("res://assets/obstacles/glass/breakingGlass_000.ogg"),
	],
	KIND_FLOOR: [
		preload("res://assets/floor/footstep_concrete_000.ogg"),
		preload("res://assets/floor/footstep_concrete_001.ogg"),
		preload("res://assets/floor/footstep_concrete_002.ogg"),
		preload("res://assets/floor/footstep_concrete_003.ogg"),
		preload("res://assets/floor/footstep_concrete_004.ogg"),
	],
}

## Instância ativa publicada para os produtores (bala). `current` é
## limpo em _exit_tree — troca de cena/home não deixa ponteiro morto.
static var current: ImpactSoundManager

## Pool de vozes (MAX_VOICES AudioStreamPlayers, filhos deste nó).
var _voices: Array[AudioStreamPlayer] = []

## Sequência de uso por voz (contador monotônico): na saturação do pool
## a voz com menor carimbo — a que toca há mais tempo — é reiniciada.
var _voice_stamp: Array[int] = []
var _play_seq := 0

## Último índice sorteado por material (anti-repetição imediata).
var _last_pick: Dictionary = {}


func _ready() -> void:
	current = self
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % (i + 1)
		add_child(voice)
		_voices.append(voice)
		_voice_stamp.append(0)


func _exit_tree() -> void:
	if current == self:
		current = null


## Reproduz um impacto de `material` no pool de vozes. Chamado SOMENTE
## pelo roteador da bala, em impactos já deduplicados — este método não
## decide sincronização, apenas variação e mixagem. Material fora do
## mapa cai no chão (fallback); sem pool (nó fora da árvore) é no-op.
func play(material: StringName) -> void:
	if _voices.is_empty():
		return
	var stream := _pick_stream(material)
	if stream == null:
		return
	_start_voice(stream, material)


## Para todas as vozes imediatamente. Chamado na troca de fase
## (game.gd/load_level): nenhum som da fase anterior sobrevive.
func stop_all() -> void:
	for voice in _voices:
		voice.stop()


## Pool de arquivos de `material` (fallback: chão). Exposto para
## testes/inspeção, no padrão de ImpactTextManager.texts_for.
static func sounds_for(material: StringName) -> Array:
	var pool: Array = SOUNDS_BY_MATERIAL.get(material, [])
	if not pool.is_empty():
		return pool
	return SOUNDS_BY_MATERIAL.get(KIND_FLOOR, [])


## Volume final (dB) de `material`: global + trim do material.
func volume_for(material: StringName) -> float:
	return SFX_VOLUME_DB + float(VOLUME_DB_BY_MATERIAL.get(material, 0.0))


## Pitch de `material`: faixa do Glass (arquivo único) ou micro-jitter
## simétrico em torno de 1.0 para os demais.
func pitch_for(material: StringName) -> float:
	if material == ObstacleDefinition.KIND_GLASS:
		return randf_range(GLASS_PITCH_MIN, GLASS_PITCH_MAX)
	return 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)


## Offset inicial (s) de `material` (ver START_OFFSET_BY_MATERIAL).
func start_offset_for(material: StringName) -> float:
	return float(START_OFFSET_BY_MATERIAL.get(material, 0.0))


## Sorteia um arquivo do material SEM repetir o índice imediatamente
## anterior quando há alternativas: exclui o último índice e sorteia
## uniforme entre os demais (randi() % (n-1) remapeado), o que mantém
## cada arquivo com probabilidade marginal igual — distribuição
## equilibrada por construção, sem viés para os primeiros índices.
## Pool de 1 arquivo devolve sempre o mesmo (o pitch do Glass cobre a
## variação). Material sem arquivo devolve null (no-op do play()).
func _pick_stream(material: StringName) -> AudioStream:
	var pool := sounds_for(material)
	if pool.is_empty():
		return null
	if pool.size() == 1:
		return pool[0]
	var last := int(_last_pick.get(material, -1))
	var pick: int
	if last < 0 or last >= pool.size():
		pick = randi() % pool.size()
	else:
		pick = randi() % (pool.size() - 1)
		if pick >= last:
			pick += 1
	_last_pick[material] = pick
	return pool[pick]


## Atributos de mixagem + início da reprodução na voz adquirida.
func _start_voice(stream: AudioStream, material: StringName) -> void:
	var voice := _acquire_voice()
	voice.volume_db = volume_for(material)
	voice.pitch_scale = pitch_for(material)
	voice.stream = stream
	voice.play(start_offset_for(material))
	_play_seq += 1
	_voice_stamp[_voices.find(voice)] = _play_seq


## Voz livre ou, na saturação, a que toca há mais tempo (menor carimbo).
func _acquire_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	var oldest := 0
	for i in range(1, _voices.size()):
		if _voice_stamp[i] < _voice_stamp[oldest]:
			oldest = i
	return _voices[oldest]
