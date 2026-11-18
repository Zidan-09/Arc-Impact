class_name SettingsManager extends RefCounted
## Hub central das preferências do jogador (volumes + inversão do eixo Y).
##
## Arquivo: `user://settings.json` (JSON simples, SEPARADO do
## `user://save.json` do SaveManager). A separação é intencional: o reset
## de progresso (`SaveManager.reset_progress`) regrava SÓ o save, então
## as configurações sobrevivem ao reset por construção — nenhum código
## precisa lembrar de preservá-las.
##
## Garantias (mesmo padrão do SaveManager):
## - Primeira execução sem arquivo cria as configurações padrão.
## - Arquivo ausente, vazio, corrompido ou com valores inválidos resulta
##   nos padrões sem quebrar a inicialização.
## - Volumes são inteiros de 0 a 100 (porcentagem exibida na tela).
## - Escrita atômica (temp + rename, com `.bak`) e só quando há mudança.
## - Salvamento automático a cada alteração: nenhum botão de salvar.
##
## Propagação sem acoplamento reverso: a tela de configurações chama
## SOMENTE os setters daqui; este hub aplica os volumes nos gerenciadores
## de áudio (`apply_audio`) e traduz a entrada da mira (`angle_input`).
## Nenhuma outra parte do projeto lê o arquivo de configurações.

const SETTINGS_PATH := "user://settings.json"
const SETTINGS_VERSION := 1

## Padrões da primeira execução: volumes cheios, sem inversão (comportamento
## atual do canhão preservado até o jogador optar).
const DEFAULT_MUSIC_VOLUME := 100
const DEFAULT_SFX_VOLUME := 100
const DEFAULT_INVERT_Y := false

const MIN_VOLUME := 0
const MAX_VOLUME := 100

## Nível do mute em dB: 0% desliga na prática sem usar -INF (que o
## AudioServer trata como silêncio total, mas polui comparações).
const MUTE_DB := -80.0

static var _music_volume := DEFAULT_MUSIC_VOLUME
static var _sfx_volume := DEFAULT_SFX_VOLUME
static var _invert_y := DEFAULT_INVERT_Y
static var _loaded := false


## Carrega as configurações (da memória após a primeira leitura). Sempre
## retorna valores válidos; nunca falha. Roda ANTES da primeira reprodução
## de áudio (os Autoloads de música/sons leem daqui no próprio `_ready`).
static func load_settings(path: String = SETTINGS_PATH) -> Dictionary:
	_ensure_loaded(path)
	return {
		"music_volume": _music_volume,
		"sfx_volume": _sfx_volume,
		"invert_y": _invert_y,
	}


static func get_music_volume(path: String = SETTINGS_PATH) -> int:
	_ensure_loaded(path)
	return _music_volume


static func get_sfx_volume(path: String = SETTINGS_PATH) -> int:
	_ensure_loaded(path)
	return _sfx_volume


static func is_invert_y(path: String = SETTINGS_PATH) -> bool:
	_ensure_loaded(path)
	return _invert_y


## Define o volume da música (0..100, clampado). Salva e aplica
## imediatamente; retorna true quando gravou, false quando o valor é o
## mesmo (sem escrita redundante) ou a gravação falhou.
static func set_music_volume(value: int, path: String = SETTINGS_PATH) -> bool:
	_ensure_loaded(path)
	var clean := clampi(value, MIN_VOLUME, MAX_VOLUME)
	if clean == _music_volume:
		return false
	if not _write_dict(clean, _sfx_volume, _invert_y, path):
		return false
	_music_volume = clean
	apply_audio()
	return true


## Define o volume dos efeitos (0..100, clampado). Independente da música.
static func set_sfx_volume(value: int, path: String = SETTINGS_PATH) -> bool:
	_ensure_loaded(path)
	var clean := clampi(value, MIN_VOLUME, MAX_VOLUME)
	if clean == _sfx_volume:
		return false
	if not _write_dict(_music_volume, clean, _invert_y, path):
		return false
	_sfx_volume = clean
	apply_audio()
	return true


## Liga/desliga a inversão do eixo Y da mira do canhão.
static func set_invert_y(enabled: bool, path: String = SETTINGS_PATH) -> bool:
	_ensure_loaded(path)
	if enabled == _invert_y:
		return false
	if not _write_dict(_music_volume, _sfx_volume, enabled, path):
		return false
	_invert_y = enabled
	return true


## Traduz a entrada vertical da mira para o delta do canhão. ÚNICO ponto
## que conhece a inversão: com ela desligada devolve `-relative.y`
## (comportamento atual); ligada, `+relative.y`. A física dos disparos
## nunca passa por aqui — só a interpretação da entrada.
static func angle_input(relative_y: float, path: String = SETTINGS_PATH) -> float:
	_ensure_loaded(path)
	if _invert_y:
		return relative_y
	return -relative_y


## Propaga os volumes atuais para todos os gerenciadores de áudio ativos.
## Cada gerenciador mantém seu trim próprio (fundo da música, cliques de
## interface, materiais de impacto); aqui entra SÓ o ganho do nível.
## Chamadores nulos são ignorados (cenas sem aquele gerenciador).
static func apply_audio() -> void:
	var music_level := float(_music_volume) / 100.0
	var sfx_level := float(_sfx_volume) / 100.0
	if BackgroundMusicManager.current != null:
		BackgroundMusicManager.current.set_music_level(music_level)
	if InterfaceSoundManager.current != null:
		InterfaceSoundManager.current.set_sfx_level(sfx_level)
	if ImpactSoundManager.current != null:
		ImpactSoundManager.current.set_sfx_level(sfx_level)


## Ganho em dB de um nível 0.0..1.0 sobre o trim do gerenciador: 100% =
## +0 dB (trim intacto), 50% ≈ -6 dB, 0% = mute. Ponto ÚNICO de conversão
## porcentagem → dB (música e SFX usam a mesma curva).
static func level_to_db_gain(level01: float) -> float:
	var clean := clampf(level01, 0.0, 1.0)
	if clean <= 0.001:
		return MUTE_DB
	return linear_to_db(clean)


## Zera o cache em memória (uso em testes).
static func reset_cache() -> void:
	_loaded = false
	_music_volume = DEFAULT_MUSIC_VOLUME
	_sfx_volume = DEFAULT_SFX_VOLUME
	_invert_y = DEFAULT_INVERT_Y


static func _ensure_loaded(path: String) -> void:
	if _loaded:
		return
	var data := _read_file(path)
	if data.is_empty():
		# Sem arquivo válido: (re)cria com os padrões.
		_write_dict(DEFAULT_MUSIC_VOLUME, DEFAULT_SFX_VOLUME, DEFAULT_INVERT_Y, path)
		_music_volume = DEFAULT_MUSIC_VOLUME
		_sfx_volume = DEFAULT_SFX_VOLUME
		_invert_y = DEFAULT_INVERT_Y
	else:
		_music_volume = int(data["music_volume"])
		_sfx_volume = int(data["sfx_volume"])
		_invert_y = bool(data["invert_y"])
	_loaded = true


static func _backup_path(path: String) -> String:
	return path + ".bak"


static func _tmp_path(path: String) -> String:
	return path + ".tmp"


## Lê e valida um arquivo. Retorna {} quando ausente/inválido.
static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SettingsManager: não foi possível abrir '%s'." % path)
		return {}
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SettingsManager: configurações corrompidas em '%s' (JSON inválido)." % path)
		return {}
	var data: Dictionary = parsed
	var music := _sanitize_volume(data.get("music_volume", -1))
	var sfx := _sanitize_volume(data.get("sfx_volume", -1))
	return {
		"music_volume": music if music >= MIN_VOLUME else DEFAULT_MUSIC_VOLUME,
		"sfx_volume": sfx if sfx >= MIN_VOLUME else DEFAULT_SFX_VOLUME,
		"invert_y": data["invert_y"] if data.get("invert_y") is bool else DEFAULT_INVERT_Y,
	}


## Volume válido: inteiro de 0 a 100. JSON decodifica números como float,
## então aceita 80.0 como 80. Retorna -1 quando inválido (fora da faixa
## invalida o campo, que volta ao padrão sem contaminar os demais).
static func _sanitize_volume(value: Variant) -> int:
	if value is bool:
		return -1
	if value is int and value >= MIN_VOLUME and value <= MAX_VOLUME:
		return value
	if value is float and value == floor(value) and value >= MIN_VOLUME and value <= MAX_VOLUME:
		return int(value)
	return -1


## Serializa e grava de forma atômica (mesmo protocolo do SaveManager:
## escreve no `.tmp`, preserva o atual como `.bak` e renomeia por cima).
static func _write_dict(music_volume: int, sfx_volume: int, invert_y: bool, path: String) -> bool:
	if music_volume < MIN_VOLUME or music_volume > MAX_VOLUME:
		return false
	if sfx_volume < MIN_VOLUME or sfx_volume > MAX_VOLUME:
		return false
	var payload := {
		"version": SETTINGS_VERSION,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"invert_y": invert_y,
	}
	var tmp := _tmp_path(path)
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("SettingsManager: não foi possível escrever '%s'." % tmp)
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_backup_path(path))
		var copy_err := DirAccess.copy_absolute(path, _backup_path(path))
		if copy_err != OK:
			push_warning("SettingsManager: backup das configurações falhou (%s)." % error_string(copy_err))
	if FileAccess.file_exists(path):
		# No Windows o rename por cima do destino pode falhar, então
		# remove o destino (o .bak já guarda a cópia boa).
		DirAccess.remove_absolute(path)
	var rename_err := DirAccess.rename_absolute(tmp, path)
	if rename_err != OK:
		push_warning("SettingsManager: rename das configurações falhou (%s)." % error_string(rename_err))
		return false
	return true
