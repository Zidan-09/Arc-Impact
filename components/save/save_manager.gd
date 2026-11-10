class_name SaveManager extends RefCounted
## Gerencia o progresso persistente (próxima fase desbloqueada).
##
## Arquivo: `user://save.json` (JSON simples, mecanismo persistente da
## engine — nunca diretório temporário). Guarda apenas dados puros
## (versão, fase e seed); a fase em si é sempre regenerada pelo gerador
## procedural a partir desses números.
##
## Garantias:
## - Primeira execução sem arquivo cria o save com a fase 1.
## - Arquivo ausente, vazio, corrompido ou com fase inválida resulta na
##   fase 1 sem quebrar a inicialização.
## - A fase é sempre um inteiro positivo.
## - Escrita atômica (temp + rename, com `.bak` da última gravação boa)
##   e sem escritas desnecessárias (só grava quando há mudança real).
## - O save guarda o progresso MÁXIMO: jogar/vencer uma fase anterior
##   (tela Levels) nunca regride o valor persistido.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const DEFAULT_LEVEL := 1
const DEFAULT_SEED := 1

## Últimos valores sabidamente persistidos nesta execução. Evita
## escritas desnecessárias e serve de referência monotônica.
static var _last_written_level := -1
static var _last_written_seed := -1


## Carrega o progresso. Sempre retorna {"level": int, "seed": int}
## válidos; nunca falha. Deve rodar ANTES da primeira geração de fase.
static func load_progress(path: String = SAVE_PATH) -> Dictionary:
	var result := _read_file(path)
	if result.is_empty():
		result = _read_file(_backup_path(path))
	if result.is_empty():
		# Sem arquivo válido: (re)cria com os padrões.
		var defaults := {"level": DEFAULT_LEVEL, "seed": DEFAULT_SEED}
		_write_dict(path, defaults)
		_last_written_level = DEFAULT_LEVEL
		_last_written_seed = DEFAULT_SEED
		return defaults
	_last_written_level = int(result["level"])
	_last_written_seed = int(result["seed"])
	return result


## Persiste a próxima fase/seed. Só escreve quando há mudança real e
## NUNCA regride o progresso máximo já persistido (replay de fase
## anterior, via tela Levels, não apaga nem sobrescreve o avanço).
## Retorna true quando gravou, false quando pulou (sem mudança, fase
## inválida ou downgrade) ou quando a gravação falhou.
static func save_progress(level: int, seed: int, path: String = SAVE_PATH) -> bool:
	var clean_level := _sanitize_level(level)
	var clean_seed := _sanitize_seed(seed)
	# Fase inválida (não inteira/positiva) nunca é persistida.
	if clean_level < DEFAULT_LEVEL:
		return false
	# Sem cache em memória o disco é a referência de monotonicidade.
	if _last_written_level < 0:
		var on_disk := _read_file(path)
		if not on_disk.is_empty():
			_last_written_level = int(on_disk["level"])
			_last_written_seed = int(on_disk["seed"])
	if clean_level == _last_written_level and clean_seed == _last_written_seed:
		return false
	# Evita downgrade: se o disco/cache já tem progresso maior, um valor
	# menor (vitória numa fase antiga) é descartado.
	if clean_level < _last_written_level:
		return false
	var ok := _write_dict(path, {"level": clean_level, "seed": clean_seed})
	if ok:
		_last_written_level = clean_level
		_last_written_seed = clean_seed
	return ok


## Seed da fase `level` seguindo a regra existente de progressão: a
## seed avança +1 a cada fase (ver `game.gd`: `load_level(current_seed
## + 1, level_number + 1)`). O par `(base_level, base_seed)` vem do
## save e funciona como âncora: para a fase máxima ele devolve
## exatamente a seed persistida (reprodução determinística da fase ao
## voltar por ela na tela Levels) e para as fases anteriores estende a
## mesma regra +1.
static func seed_for_level(level: int, base_level: int, base_seed: int) -> int:
	return base_seed + (level - base_level)


## Zera o progresso para a fase 1 (botão "Reset" da home). Diferente de
## `save_progress`, o downgrade aqui é intencional: força a gravação
## mesmo com progresso maior em disco e regrava sempre, garantindo que o
## arquivo exista com os valores padrão (fase 1, seed inicial).
static func reset_progress(path: String = SAVE_PATH) -> bool:
	var ok := _write_dict(path, {"level": DEFAULT_LEVEL, "seed": DEFAULT_SEED})
	if ok:
		_last_written_level = DEFAULT_LEVEL
		_last_written_seed = DEFAULT_SEED
	return ok


## Zera o cache em memória (uso em testes).
static func reset_cache() -> void:
	_last_written_level = -1
	_last_written_seed = -1


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
		push_warning("SaveManager: não foi possível abrir '%s'." % path)
		return {}
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SaveManager: save corrompido em '%s' (JSON inválido)." % path)
		return {}
	var data: Dictionary = parsed
	var level := _sanitize_level(data.get("level", -1))
	# Nível inválido contamina o save inteiro: volta para a fase 1.
	if level < 0:
		push_warning("SaveManager: nível inválido no save ('%s'), usando fase 1." % path)
		return {}
	return {"level": level, "seed": _sanitize_seed(data.get("seed", DEFAULT_SEED))}


## Nível válido: inteiro >= 1. JSON decodifica números como float,
## então aceita 2.0 como 2. Retorna -1 quando inválido.
static func _sanitize_level(value: Variant) -> int:
	if value is bool:
		return -1
	if value is int and value >= 1:
		return value
	if value is float and value >= 1.0 and value == floor(value):
		return int(value)
	return -1


## Seed válida: inteiro. Qualquer inteiro serve ao gerador; valores
## não-inteiros voltam ao padrão sem invalidar o save.
static func _sanitize_seed(value: Variant) -> int:
	if value is bool:
		return DEFAULT_SEED
	if value is int:
		return value
	if value is float and value == floor(value):
		return int(value)
	return DEFAULT_SEED


## Serializa e grava de forma atômica: escreve no `.tmp`, preserva o
## arquivo atual como `.bak` e renomeia por cima. Um crash deixa ou o
## save antigo ou o novo — nunca um arquivo meio escrito.
static func _write_dict(path: String, data: Dictionary) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"level": int(data["level"]),
		"seed": int(data["seed"]),
	}
	var tmp := _tmp_path(path)
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: não foi possível escrever '%s'." % tmp)
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_backup_path(path))
		var copy_err := DirAccess.copy_absolute(path, _backup_path(path))
		if copy_err != OK:
			push_warning("SaveManager: backup do save falhou (%s)." % error_string(copy_err))
	if FileAccess.file_exists(path):
		# No Windows o rename por cima do destino pode falhar, então
		# remove o destino (o .bak já guarda a cópia boa).
		DirAccess.remove_absolute(path)
	var rename_err := DirAccess.rename_absolute(tmp, path)
	if rename_err != OK:
		push_warning("SaveManager: rename do save falhou (%s)." % error_string(rename_err))
		return false
	return true
