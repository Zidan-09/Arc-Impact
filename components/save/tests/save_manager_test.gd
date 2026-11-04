extends SceneTree
## Teste do SaveManager: criação na primeira execução, incremento por
## vitória, persistência entre sessões e robustez contra save inválido.
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/save/tests/save_manager_test.gd
## Saída: "SAVE_MANAGER_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).
## Usa um arquivo isolado (`TEST_PATH`) para nunca tocar no save real.
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.

const TEST_PATH := "user://save_manager_test.json"


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var failures := 0
	failures += _check_first_run_creates()
	failures += _check_win_increments()
	failures += _check_persistence_across_sessions()
	failures += _check_invalid_saves()
	failures += _check_no_redundant_writes()
	_cleanup()
	if failures == 0:
		print("SAVE_MANAGER_TEST: PASS")
	else:
		printerr("SAVE_MANAGER_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


func _cleanup() -> void:
	SaveManager.reset_cache()
	for suffix in ["", ".tmp", ".bak"]:
		var p := TEST_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.flush()
	file.close()


func _check_first_run_creates() -> int:
	_cleanup()
	var progress: Dictionary = SaveManager.load_progress(TEST_PATH)
	if int(progress["level"]) != 1:
		printerr("  [first-run] nível esperado 1, veio %s." % str(progress.get("level")))
		return 1
	if not FileAccess.file_exists(TEST_PATH):
		printerr("  [first-run] arquivo de save não foi criado.")
		return 1
	return 0


func _check_win_increments() -> int:
	_cleanup()
	SaveManager.load_progress(TEST_PATH) # cria com fase 1
	# Vitória na fase 1 -> próxima fase 2 (mesmo contrato de game.gd).
	if not SaveManager.save_progress(2, 2, TEST_PATH):
		printerr("  [win] primeira gravação deveria ter acontecido.")
		return 1
	var back: Dictionary = SaveManager.load_progress(TEST_PATH)
	if int(back["level"]) != 2:
		printerr("  [win] nível esperado 2, veio %s." % str(back.get("level")))
		return 1
	# Vitória na fase 2 -> fase 3.
	SaveManager.save_progress(3, 3, TEST_PATH)
	back = SaveManager.load_progress(TEST_PATH)
	if int(back["level"]) != 3:
		printerr("  [win] nível esperado 3, veio %s." % str(back.get("level")))
		return 1
	return 0


func _check_persistence_across_sessions() -> int:
	_cleanup()
	SaveManager.load_progress(TEST_PATH)
	SaveManager.save_progress(3, 3, TEST_PATH)
	# Nova "sessão": limpa só o cache em memória, o disco permanece.
	SaveManager.reset_cache()
	var back: Dictionary = SaveManager.load_progress(TEST_PATH)
	if int(back["level"]) != 3 or int(back["seed"]) != 3:
		printerr("  [reopen] esperado level=3 seed=3, veio %s." % str(back))
		return 1
	return 0


func _check_invalid_saves() -> int:
	var cases := {
		"empty": "",
		"blank": "   \n  ",
		"garbage": "não é json {{{",
		"array": "[1, 2, 3]",
		"zero": '{"version":1,"level":0,"seed":1}',
		"negative": '{"version":1,"level":-5,"seed":1}',
		"string": '{"version":1,"level":"dez","seed":1}',
		"fraction": '{"version":1,"level":2.5,"seed":1}',
		"bool": '{"version":1,"level":true,"seed":1}',
		"null": '{"version":1,"level":null,"seed":1}',
		"missing": '{"version":1,"seed":7}',
	}
	for key in cases:
		_cleanup()
		_write_raw(TEST_PATH, String(cases[key]))
		var progress: Dictionary = SaveManager.load_progress(TEST_PATH)
		if int(progress["level"]) != 1:
			printerr("  [corrupt:%s] esperado fallback para fase 1, veio %s." % [key, str(progress.get("level"))])
			return 1
	# Número inteiro em float (2.0) é JSON válido para a fase 2.
	_cleanup()
	_write_raw(TEST_PATH, '{"version":1,"level":2.0,"seed":2.0}')
	var ok_float: Dictionary = SaveManager.load_progress(TEST_PATH)
	if int(ok_float["level"]) != 2:
		printerr("  [float] esperado fase 2, veio %s." % str(ok_float.get("level")))
		return 1
	return 0


func _check_no_redundant_writes() -> int:
	_cleanup()
	SaveManager.load_progress(TEST_PATH) # cria com fase 1
	if SaveManager.save_progress(1, 1, TEST_PATH):
		printerr("  [write] gravação sem mudança deveria ser pulada.")
		return 1
	if not SaveManager.save_progress(2, 2, TEST_PATH):
		printerr("  [write] mudança real deveria gravar.")
		return 1
	if SaveManager.save_progress(2, 2, TEST_PATH):
		printerr("  [write] segunda gravação idêntica deveria ser pulada.")
		return 1
	if not FileAccess.file_exists(TEST_PATH + ".bak"):
		printerr("  [write] backup .bak da última gravação boa não existe.")
		return 1
	return 0
