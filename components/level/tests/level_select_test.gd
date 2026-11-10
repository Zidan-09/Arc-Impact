extends SceneTree
## Teste de integração da tela Levels: seleção de fase, bloqueio de fases
## locked, navegação completa (Home -> Levels -> jogo -> Levels -> Home)
## e persistência do progresso máximo durante um replay.
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/level/tests/level_select_test.gd
## Saída: "LEVEL_SELECT_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).
## Faz backup/restore de `user://save.json` (+ `.bak`) para nunca alterar
## o save real do usuário.

const GAME_SCRIPT := preload("res://screens/game.gd")
const FAST_GEN := preload("res://components/level/fast_level_generator.gd")

const HOME_SCENE := "res://screens/home.tscn"
const LEVELS_SCENE := "res://screens/levels.tscn"
const GAME_SCENE := "res://screens/game.tscn"

const SAVE_PATH := "user://save.json"
const SAVE_BAK := "user://save.json.levels_test.bak"
const SAVE_INTERNAL_BAK := "user://save.json.bak"
const SAVE_INTERNAL_BAK_BAK := "user://save.json.bak.levels_test.bak"

const SAVE_LEVEL := 10
const SAVE_SEED := 10
const MAX_WAIT_FRAMES := 300

var failures := 0
var _save_existed := false
var _internal_bak_existed := false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_backup_save()
	# Progresso de partida: fase 10 desbloqueada.
	SaveManager.reset_cache()
	SaveManager.save_progress(SAVE_LEVEL, SAVE_SEED)
	SaveManager.reset_cache()

	# Home -> Levels (o mesmo caminho do botão FASES da home).
	GAME_SCRIPT.requested_level = 0
	GAME_SCRIPT.return_scene = HOME_SCENE
	change_scene_to_file(LEVELS_SCENE)
	var levels = await _wait_scene(LEVELS_SCENE, "tela Levels")
	if levels != null:
		failures += await _check_levels_screen(levels)
		if failures == 0:
			failures += await _check_select_and_play(levels)
	_restore_save()
	if failures == 0:
		print("LEVEL_SELECT_TEST: PASS")
	else:
		printerr("LEVEL_SELECT_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


## Espera a troca de cena (change_scene é deferido) e devolve a cena atual.
func _wait_scene(path: String, label: String) -> Node:
	for _i in range(MAX_WAIT_FRAMES):
		if current_scene != null and String(current_scene.scene_file_path) == path:
			return current_scene
		await process_frame
	printerr("  [scene] %s não apareceu (%s)." % [label, path])
	failures += 1
	return null


## Espera uma condição (Callable -> bool) por até `frames` frames.
func _wait_until(cond: Callable, frames: int) -> bool:
	for _i in range(frames):
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())


## Tela Levels: progresso exibido, estados dos nós, bloqueio de fase
## locked e posição automática na fase atual.
func _check_levels_screen(levels) -> int:
	var local := 0
	var subtitle: Label = levels.get_node("Header/Subtitle")
	if subtitle.text != "Progresso: fase %d" % SAVE_LEVEL:
		printerr("  [levels] subtítulo '%s', esperado 'Progresso: fase %d'." % [subtitle.text, SAVE_LEVEL])
		local += 1
	var map = levels.get_node("MapArea/LevelMap")
	if not await _wait_until(_frontier_is.bind(map), 120):
		printerr("  [levels] mapa não montou a fronteira %d (veio %d)." % [SAVE_LEVEL, map.frontier])
		return local + 1
	# Estados: concluída antes da fronteira e atual na fronteira.
	for level in [5, SAVE_LEVEL - 1]:
		if not map._nodes.has(level):
			printerr("  [levels] fase %d não carregada na janela inicial." % level)
			local += 1
		elif map._nodes[level].state != map._nodes[level].State.DONE:
			printerr("  [levels] fase %d não está DONE (state=%d)." % [level, map._nodes[level].state])
			local += 1
	if not map._nodes.has(SAVE_LEVEL):
		printerr("  [levels] nó da fase atual não carregado.")
		local += 1
	elif map._nodes[SAVE_LEVEL].state != map._nodes[SAVE_LEVEL].State.CURRENT:
		printerr("  [levels] fase atual não está em CURRENT.")
		local += 1
	# A abertura foca a região da fase atual (não o início da trilha).
	if not await _wait_until(_has_level.bind(map, SAVE_LEVEL + 1), 60):
		printerr("  [levels] mapa não focou a região da fase atual (fase %d ausente)." % (SAVE_LEVEL + 1))
		return local + 1
	var locked = map._nodes[SAVE_LEVEL + 1]
	if locked.state != locked.State.LOCKED:
		printerr("  [levels] fase %d deveria estar LOCKED (state=%d)." % [SAVE_LEVEL + 1, locked.state])
		local += 1
	# Clique em fase bloqueada: hint visível, NENHUMA troca de cena e
	# nenhuma mudança no estado de sessão.
	var path_antes := String(current_scene.scene_file_path)
	_press(locked, Vector2(48.0, 48.0))
	_release(locked, Vector2(48.0, 48.0))
	await process_frame
	var hint: Label = levels.get_node("Hint")
	if not hint.visible or not String(hint.text).contains("bloqueada"):
		printerr("  [levels] clique bloqueado sem feedback (visible=%s, text='%s')." % [
			str(hint.visible), String(hint.text)
		])
		local += 1
	if String(current_scene.scene_file_path) != path_antes:
		printerr("  [levels] clique em fase bloqueada trocou de cena.")
		local += 1
	if GAME_SCRIPT.requested_level != 0:
		printerr("  [levels] clique bloqueado definiu requested_level=%d." % GAME_SCRIPT.requested_level)
		local += 1
	return local


## Seleciona uma fase desbloqueada e percorre o ciclo completo:
## jogo -> vitória/replay (save intacto) -> next -> home -> Levels -> Home.
func _check_select_and_play(levels) -> int:
	var local := 0
	var map = levels.get_node("MapArea/LevelMap")
	# Escolhe a fase 3 (desbloqueada, anterior à atual: replay).
	map.focus_level(3)
	if not await _wait_until(_has_level.bind(map, 3), 60):
		printerr("  [select] mapa não carregou a fase 3 após o foco.")
		return 1
	_press(map._nodes[3], Vector2(48.0, 48.0))
	_release(map._nodes[3], Vector2(48.0, 48.0))
	var game = await _wait_scene(GAME_SCENE, "cena do jogo")
	if game == null:
		return 1

	# A fase 3 exata, com a seed derivada da regra +1 ancorada no save
	# (10/10 -> seed 3) e a def idêntica à do gerador existente.
	if not await _wait_until(_not_loading.bind(game), MAX_WAIT_FRAMES):
		printerr("  [select] fase 3 não terminou de carregar.")
		local += 1
	if int(game.level_number) != 3:
		printerr("  [select] level_number=%d, esperado 3." % int(game.level_number))
		local += 1
	var want_seed := SaveManager.seed_for_level(3, SAVE_LEVEL, SAVE_SEED)
	if int(game.current_seed) != want_seed:
		printerr("  [select] current_seed=%d, esperado %d." % [int(game.current_seed), want_seed])
		local += 1
	if GAME_SCRIPT.requested_level != 0:
		printerr("  [select] requested_level não foi consumido (=%d)." % GAME_SCRIPT.requested_level)
		local += 1
	if String(GAME_SCRIPT.return_scene) != LEVELS_SCENE:
		printerr("  [select] return_scene='%s', esperado Levels." % String(GAME_SCRIPT.return_scene))
		local += 1
	var gen: Dictionary = FAST_GEN.generate(want_seed, 3)
	if bool(gen.get("fallback_used", true)):
		printerr("  [select] gerador usou fallback na fase 3: %s." % str(gen.get("log")))
		local += 1
	if game.current_def == null:
		printerr("  [select] def da fase 3 ausente.")
		local += 1
	elif JSON.stringify(game.current_def.to_dict()) != JSON.stringify((gen["def"] as LevelDefinition).to_dict()):
		printerr("  [select] def do jogo difere do gerador (seed %d, fase 3)." % want_seed)
		local += 1

	# Replay: vencer a fase 3 NÃO regride nem altera o save (fase 10).
	game._on_target_hit(null)
	await process_frame
	local += _check_save_level(SAVE_LEVEL, "vitória em replay")
	# Next: avança para a fase 4 na tela, com o save ainda em 10.
	game._on_popup_next()
	if not await _wait_until(_not_loading.bind(game), MAX_WAIT_FRAMES):
		printerr("  [select] fase 4 (next) não terminou de carregar.")
		local += 1
	if int(game.level_number) != 4:
		printerr("  [select] após next level_number=%d, esperado 4." % int(game.level_number))
		local += 1
	local += _check_save_level(SAVE_LEVEL, "next a partir do replay")

	# Home: retorna para a tela Levels (return_scene) e o progresso
	# continua intacto.
	game._on_popup_home()
	var levels2 = await _wait_scene(LEVELS_SCENE, "retorno à tela Levels")
	if levels2 == null:
		return local
	var map2 = levels2.get_node_or_null("MapArea/LevelMap")
	if map2 == null or not await _wait_until(_frontier_is.bind(map2), 120):
		printerr("  [home] Levels reaberta sem a fronteira %d." % SAVE_LEVEL)
		local += 1
	local += _check_save_level(SAVE_LEVEL, "retorno via popup Home")

	# Back da Levels volta para a Home.
	levels2.get_node("Header/Back/Home").pressed.emit()
	var home = await _wait_scene(HOME_SCENE, "retorno à Home")
	if home == null:
		local += 1
	return local


func _frontier_is(map) -> bool:
	return int(map.frontier) == SAVE_LEVEL


func _has_level(map, level: int) -> bool:
	return bool(map._nodes.has(level))


func _not_loading(game) -> bool:
	return not bool(game._loading)


func _check_save_level(want: int, contexto: String) -> int:
	SaveManager.reset_cache()
	var progress: Dictionary = SaveManager.load_progress()
	if int(progress["level"]) != want or int(progress["seed"]) != SAVE_SEED:
		printerr("  [save:%s] esperado %d/%d, veio %s." % [
			contexto, want, SAVE_SEED, str(progress)
		])
		return 1
	return 0


func _press(node, local_pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local_pos
	node._gui_input(ev)


func _release(node, local_pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = local_pos
	node._gui_input(ev)


func _backup_save() -> void:
	_save_existed = FileAccess.file_exists(SAVE_PATH)
	if _save_existed:
		DirAccess.copy_absolute(SAVE_PATH, SAVE_BAK)
	_internal_bak_existed = FileAccess.file_exists(SAVE_INTERNAL_BAK)
	if _internal_bak_existed:
		DirAccess.copy_absolute(SAVE_INTERNAL_BAK, SAVE_INTERNAL_BAK_BAK)


func _restore_save() -> void:
	SaveManager.reset_cache()
	if _save_existed:
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)
		DirAccess.copy_absolute(SAVE_BAK, SAVE_PATH)
		DirAccess.remove_absolute(SAVE_BAK)
	if _internal_bak_existed:
		if FileAccess.file_exists(SAVE_INTERNAL_BAK):
			DirAccess.remove_absolute(SAVE_INTERNAL_BAK)
		DirAccess.copy_absolute(SAVE_INTERNAL_BAK_BAK, SAVE_INTERNAL_BAK)
		DirAccess.remove_absolute(SAVE_INTERNAL_BAK_BAK)
	SaveManager.reset_cache()
