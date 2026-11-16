extends SceneTree
## Teste do popup de fim de fase (vitória/derrota/pausa): a linha de botões
## muda conforme a modalidade — no popup de pausa o retry é substituído
## pelo botão de fases (que abre a tela Levels), na vitória e na derrota o
## retry permanece. Roda headless, sem framework:
##   godot --headless --path . -s res://components/game-popup/tests/game_popup_test.gd
## Saída: "GAME_POPUP_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).
## Não grava o save: o teste só navega entre as telas.

const GAME_SCENE := "res://screens/game.tscn"
const LEVELS_SCENE := "res://screens/levels.tscn"
const MAX_WAIT_FRAMES := 300

var failures := 0


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	change_scene_to_file(GAME_SCENE)
	var game = await _wait_scene(GAME_SCENE)
	if game == null:
		printerr("  [game] cena do jogo não abriu.")
		quit(1)
		return
	if not await _wait_until(_not_loading.bind(game), MAX_WAIT_FRAMES):
		printerr("  [game] fase não terminou de carregar.")
		failures += 1
	var popup = game.get("victory_popup")
	var tree := game.get_tree()

	# Pausa: botão de fases no lugar do retry.
	game._on_pause_pressed()
	await process_frame
	_check(popup.visible, "pausa: popup visível")
	_check(popup.levels_button.visible, "pausa: botão de fases visível")
	_check(not popup.retry_button.visible, "pausa: retry oculto")
	_check(popup.next_button.visible, "pausa: botão de continuar visível")

	# Derrota: retry permanece, botão de fases oculto.
	popup.show_defeat_popup(0, 0)
	await process_frame
	_check(popup.retry_button.visible, "derrota: retry visível")
	_check(not popup.levels_button.visible, "derrota: botão de fases oculto")
	_check(not popup.next_button.visible, "derrota: next oculto")

	# Vitória: retry permanece, botão de fases oculto.
	popup.show_popup(0, 0)
	await process_frame
	_check(popup.retry_button.visible, "vitória: retry visível")
	_check(not popup.levels_button.visible, "vitória: botão de fases oculto")

	# Navegação: o botão de fases do popup de pausa abre a tela Levels
	# e despausa a árvore.
	game._on_pause_pressed()
	await process_frame
	popup.levels_button.pressed.emit()
	if await _wait_scene(LEVELS_SCENE) == null:
		printerr("  [levels] botão de fases não abriu a tela de fases.")
		failures += 1
	_check(not tree.paused, "árvore despausada após abrir as fases")

	if failures == 0:
		print("GAME_POPUP_TEST: PASS")
	else:
		printerr("GAME_POPUP_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


## Espera a troca de cena (change_scene é deferido) e devolve a cena atual.
func _wait_scene(path: String) -> Node:
	for _i in range(MAX_WAIT_FRAMES):
		if current_scene != null and String(current_scene.scene_file_path) == path:
			return current_scene
		await process_frame
	return null


## Espera uma condição (Callable -> bool) por até `frames` frames.
func _wait_until(cond: Callable, frames: int) -> bool:
	for _i in range(frames):
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())


func _not_loading(game) -> bool:
	return not bool(game._loading)


func _check(cond: bool, label: String) -> void:
	if not cond:
		printerr("  [check] %s" % label)
		failures += 1
