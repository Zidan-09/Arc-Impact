extends SceneTree
## Teste do LevelMap: virtualização (janela + pool), estados dos nós,
## caminho orgânico, foco automático na fase atual e ativação/clique
## (inclusive arrasto longo que NÃO deve ativar). Roda headless, sem
## framework:
##   godot --headless --path . -s res://components/level-map/tests/level_map_test.gd
## Saída: "LEVEL_MAP_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).

const LevelMapScene := preload("res://components/level-map/LevelMap.tscn")
const LevelMapScript := preload("res://components/level-map/level_map.gd")

const FRONTIER := 4
const MAX_WAIT_FRAMES := 60


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var failures := 0
	var map: Control = LevelMapScene.instantiate()
	root.add_child(map)
	# Espera o primeiro layout antes de medir/rolar.
	var frames := 0
	while map.size.x <= 0.0 and frames < MAX_WAIT_FRAMES:
		await process_frame
		frames += 1
	if map.size.x <= 0.0:
		printerr("  [setup] mapa sem tamanho após %d frames." % MAX_WAIT_FRAMES)
		quit(1)
		return
	await map.setup(FRONTIER)
	await process_frame
	failures += await _check_initial_window(map)
	failures += await _check_states(map)
	failures += await _check_path(map)
	failures += await _check_focus(map)
	failures += await _check_scroll_virtualization(map)
	failures += await _check_activation(map)
	map.queue_free()
	await process_frame
	if failures == 0:
		print("LEVEL_MAP_TEST: PASS")
	else:
		printerr("LEVEL_MAP_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


## Janela inicial contígua, limitada (milhares de fases não viram milhares
## de nós) e com o pool vazio.
func _check_initial_window(map) -> int:
	await process_frame
	if map.frontier != FRONTIER:
		printerr("  [window] frontier esperado %d, veio %d." % [FRONTIER, map.frontier])
		return 1
	if map.last_level < 10000:
		printerr("  [window] trilha curta demais: last_level=%d." % map.last_level)
		return 1
	var expected: int = map._loaded_max - map._loaded_min + 1
	if map._nodes.size() != expected:
		printerr("  [window] janela não contígua: %d nós para %d fases." % [map._nodes.size(), expected])
		return 1
	var view: float = map.scroll.size.x
	var max_want := int(ceil(view / LevelMapScript.SPACING)) + 1 + LevelMapScript.MARGIN_NODES * 2
	if map._nodes.size() > max_want:
		printerr("  [window] %d nós carregados > limite %d (view=%.0f)." % [map._nodes.size(), max_want, view])
		return 1
	if map._pool.size() != 0:
		printerr("  [window] pool deveria começar vazio, veio %d." % map._pool.size())
		return 1
	return 0
## Estados visuais por relação com a fronteira: DONE antes, CURRENT na
## fronteira, LOCKED depois.
func _check_states(map) -> int:
	await process_frame
	var failures := 0
	for level in range(1, map._loaded_max + 1):
		if not map._nodes.has(level):
			continue
		var state: int = map._nodes[level].state
		var want: int
		if level > map.frontier:
			want = map._nodes[level].State.LOCKED
		elif level == map.frontier:
			want = map._nodes[level].State.CURRENT
		else:
			want = map._nodes[level].State.DONE
		if state != want:
			printerr("  [states] fase %d com estado %d, esperado %d." % [level, state, want])
			failures += 1
			break
	# Fases desbloqueadas são ativáveis; a primeira bloqueada não.
	var node_current = map._nodes[map.frontier]
	if node_current.state != node_current.State.CURRENT:
		printerr("  [states] fase atual não está em CURRENT.")
		failures += 1
	if map._nodes.has(map.frontier + 1) and map._nodes[map.frontier + 1].state != map._nodes[map.frontier + 1].State.LOCKED:
		printerr("  [states] fase %d deveria estar LOCKED." % (map.frontier + 1))
		failures += 1
	return failures
## Caminho: um ponto por nó carregado e variação vertical real (nada de
## linha perfeitamente reta).
func _check_path(map) -> int:
	await process_frame
	var failures := 0
	if map.track._points.size() != map._nodes.size():
		printerr("  [path] %d pontos para %d nós." % [map.track._points.size(), map._nodes.size()])
		failures += 1
	var ys := {}
	for p in map.track._points:
		ys[snappedf(p.y, 0.001)] = true
	if ys.size() < 2:
		printerr("  [path] caminho reto: todos os pontos na mesma altura.")
		failures += 1
	# A mesma fase cai sempre na mesma altura (determinístico).
	if LevelMapScript.y_offset(7) != LevelMapScript.y_offset(7):
		printerr("  [path] y_offset não determinístico.")
		failures += 1
	if absf(LevelMapScript.y_offset(7) - LevelMapScript.y_offset(8)) < 0.001:
		printerr("  [path] fases vizinhas com altura idêntica (sem variação).")
		failures += 1
	return failures
## Foco na fase informada: rolagem centralizada nela e o nó dela carregado.
func _check_focus(map) -> int:
	var target := 100
	map.focus_level(target)
	await map.get_tree().process_frame
	var want := clampi(int(map.center_x(target) - map.scroll.size.x * 0.5), 0, map.max_scroll())
	if absi(map.scroll.scroll_horizontal - want) > 2:
		printerr("  [focus] scroll %d, esperado ~%d." % [map.scroll.scroll_horizontal, want])
		return 1
	if not map._nodes.has(target):
		printerr("  [focus] fase %d não carregada após o foco." % target)
		return 1
	return 0
## Rolagem progressiva: a janela muda, os nós distantes vão para o pool
## (com teto) e o pool é reutilizado — nada cresce sem limite.
func _check_scroll_virtualization(map) -> int:
	var failures := 0
	# Janela/scroll de partida (região da fase 100, do teste de foco).
	var start_scroll: int = map.scroll.scroll_horizontal
	var start_window := [map._loaded_min, map._loaded_max]
	var pool_total := 0
	for target_scroll in [map.max_scroll() / 2, map.max_scroll(), 0, start_scroll]:
		map.scroll.scroll_horizontal = int(target_scroll)
		for _i in range(4):
			await map.get_tree().process_frame
		var expected: int = map._loaded_max - map._loaded_min + 1
		if map._nodes.size() != expected:
			printerr("  [scroll] janela não contígua em scroll=%d (%d nós vs %d fases)." % [
				map.scroll.scroll_horizontal, map._nodes.size(), expected
			])
			failures += 1
		if map._pool.size() > LevelMapScript.POOL_CAP:
			printerr("  [scroll] pool acima do teto: %d > %d." % [map._pool.size(), LevelMapScript.POOL_CAP])
			failures += 1
		if map.track.get_child_count() != map._nodes.size():
			printerr("  [scroll] filhos do trilho (%d) != nós vivos (%d)." % [
				map.track.get_child_count(), map._nodes.size()
			])
			failures += 1
		if map.track._points.size() != map._nodes.size():
			printerr("  [scroll] pontos do caminho (%d) != nós vivos (%d)." % [
				map.track._points.size(), map._nodes.size()
			])
			failures += 1
		pool_total = maxi(pool_total, map._pool.size())
	# Voltou ao scroll de partida: a mesma janela é refeita (reutilizando
	# os nós do pool, não criando do zero).
	if map._loaded_min != start_window[0] or map._loaded_max != start_window[1]:
		printerr("  [scroll] janela não restaurada: %d..%d (era %d..%d)." % [
			map._loaded_min, map._loaded_max, start_window[0], start_window[1]
		])
		failures += 1
	if pool_total == 0:
		printerr("  [scroll] nenhum nó foi reutilizado pelo pool (liberação não ocorreu).")
		failures += 1
	return failures
## Ativação: clique curto em fase desbloqueada seleciona; arrasto > 24px
## NÃO seleciona; fase bloqueada só emite blocked.
func _check_activation(map) -> int:
	var failures := 0
	# Volta para a região inicial (fases 1..N) para ter nós conhecidos.
	map.scroll.scroll_horizontal = 0
	for _i in range(4):
		await map.get_tree().process_frame
	var selected: Array = []
	var blocked: Array = []
	map.level_selected.connect(func(l: int): selected.append(l))
	map.blocked_selected.connect(func(l: int): blocked.append(l))

	# 1) Clique curto na fase atual (desbloqueada) -> level_selected.
	var current = map._nodes.get(map.frontier)
	if current == null:
		printerr("  [activation] nó da fase atual não está na janela inicial.")
		return 1
	_click(current, Vector2(48.0, 48.0))
	if selected.size() != 1 or selected[0] != map.frontier:
		printerr("  [activation] clique curto não ativou a fase %d (selected=%s)." % [map.frontier, str(selected)])
		failures += 1

	# 2) Arrasto longo sobre um nó desbloqueado -> NÃO ativa (rolagem).
	var done_node = map._nodes.get(1)
	if done_node == null:
		printerr("  [activation] nó da fase 1 não está carregado.")
		return 1
	_drag(done_node, Vector2(10.0, 48.0), Vector2(70.0, 48.0))
	if selected.size() != 1:
		printerr("  [activation] arrasto de %dpx ativou a fase (selected=%s)." % [
			70 - 10, str(selected)
		])
		failures += 1

	# 3) Fase bloqueada: pressionar emite blocked, nunca ativa.
	if map._nodes.has(map.frontier + 1):
		var locked = map._nodes[map.frontier + 1]
		_press(locked, Vector2(48.0, 48.0))
		if blocked.is_empty() or blocked.back() != map.frontier + 1:
			printerr("  [activation] clique em fase bloqueada não emitiu blocked (%s)." % str(blocked))
			failures += 1
		if selected.size() != 1:
			printerr("  [activation] fase bloqueada ativou o jogo (selected=%s)." % str(selected))
			failures += 1
		_release(locked, Vector2(48.0, 48.0))

	# 4) Dupla checagem do mapa: ativação "por engano" de fase além da
	#    fronteira vira blocked, nunca level_selected.
	map._on_node_activated(map.frontier + 50)
	if selected.size() != 1:
		printerr("  [activation] dupla checagem falhou: selected=%s." % str(selected))
		failures += 1
	if blocked.is_empty() or blocked.back() != map.frontier + 50:
		printerr("  [activation] dupla checagem não emitiu blocked (%s)." % str(blocked))
		failures += 1
	return failures


## Envia press+release no mesmo ponto (clique) via o caminho real do nó.
func _click(node, local_pos: Vector2) -> void:
	_press(node, local_pos)
	_release(node, local_pos)


## Press+release com deslocamento (arrasto) entre eles.
func _drag(node, from_pos: Vector2, to_pos: Vector2) -> void:
	_press(node, from_pos)
	_release(node, to_pos)


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
