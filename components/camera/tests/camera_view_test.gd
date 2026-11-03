extends SceneTree
## Teste da área visível do mundo vs. os controles da UI (GameCamera +
## geometria WorldHitArea/ControlsArea de screens/game.tscn).
##
## Garante que a fase inteira é enquadrável na área jogável — descontando a
## coluna de controles — em qualquer proporção de tela, e que nenhuma borda
## da fase fica permanentemente atrás dos controles (bug de viewport que o
## zoom/pan não resolviam).
##
## Nota: a Camera2D só materializa posição/zoom no canvas transform no
## próximo tick de frame — por isso cada mutação da câmera é seguida de
## `await process_frame` antes de ler `get_canvas_transform()`.
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/camera/tests/camera_view_test.gd

const EPS := 0.75          # tolerância em pixels
const ZOOM_EPS := 0.001    # tolerância para comparações de zoom/fit
const PAN_BIG := 100000.0
const MAX_ZOOM_FRAMES := 600
const LOAD_TRIES := 2000

## Tamanhos de viewport exercitados (o mundo ocupa `size.x - controles`).
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),  # 16:9 convencional
	Vector2i(960, 720),   # 4:3
	Vector2i(640, 1136),  # retrato / bastante alongada
	Vector2i(1920, 600),  # ultralarga
	Vector2i(500, 400),   # pequena: espaço para o mundo bem limitado
]
const DIRECTIONS: Array[Vector2] = [
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0),
	Vector2(0.0, 1.0), Vector2(0.0, -1.0),
]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# 0) Caminho real de produção: cena do jogo na viewport raiz (stretch
	#    canvas_items/expand do project.godot).
	var game_root := _instantiate_game(root)
	await _wait_loaded(game_root)
	await _run_scenarios(game_root, "viewport-raiz %s" % str(_vp_size(game_root)))
	game_root.free()
	await process_frame

	# 1) Viewports de tamanhos controlados + resize dinâmico em execução.
	var sub := SubViewport.new()
	sub.size = Vector2i(1280, 720)
	root.add_child(sub)
	var game := _instantiate_game(sub)
	await _wait_loaded(game)
	for vp_size in SIZES:
		sub.size = vp_size
		await process_frame
		await process_frame
		_check(sub.get_visible_rect().size == Vector2(vp_size),
			"viewport %s aplicada ao SubViewport" % str(vp_size))
		await _run_scenarios(game, "viewport %s" % str(vp_size))
	# Resize dinâmico durante a execução (mesmo cenário do usuário
	# redimensionando a janela).
	sub.size = Vector2i(700, 900)
	await process_frame
	await process_frame
	await _run_scenarios(game, "resize-dinamico 700x900")

	if _failures == 0:
		print("CAMERA_VIEW_TEST: PASS (%d checagens)" % _checks)
	else:
		printerr("CAMERA_VIEW_TEST: FAIL (%d/%d checagens falharam)" % [_failures, _checks])
	quit(_failures)


## Cenários de validação para a viewport atual do jogo.
func _run_scenarios(game: Node, label: String) -> void:
	var camera: GameCamera = game.game_camera
	var real_bounds: Rect2 = camera.bounds
	await _scenario(game, "%s/fase-real" % label, real_bounds)
	# Limites legados/degenerados (LevelDefinition.play_bounds padrão e o
	# fallback de _update_camera_bounds): a fase ocupa a viewport base
	# inteira — é exatamente onde o bug de sobreposição aparecia.
	await _scenario(game, "%s/bounds-1280x720" % label, Rect2(0, 0, 1280, 720))
	camera.set_bounds(real_bounds)
	await process_frame


func _scenario(game: Node, label: String, bounds: Rect2) -> void:
	var camera: GameCamera = game.game_camera
	var world_hit: Control = game.world_hit_area
	var controls: Control = game.get_node("UILayer/ControlsArea")
	var vp := camera.get_viewport_rect().size
	var view: Rect2 = world_hit.get_global_rect()
	var controls_rect: Rect2 = controls.get_global_rect()

	# --- 1) Geometria: a área do mundo é a viewport menos os controles ---
	var expected := Rect2(Vector2.ZERO, vp - Vector2(controls_rect.size.x, 0.0))
	_check(_rects_eq(view, expected, EPS),
		"%s: área do mundo = viewport - controles (%s vs %s)" % [label, str(view), str(expected)])
	if camera.has_method("view_rect"):
		_check(_rects_eq(camera.view_rect(), view, EPS),
			"%s: view_rect() da câmera coincide com a área do mundo" % label)
	_check(view.end.x <= controls_rect.position.x + EPS,
		"%s: área do mundo não invade a coluna de controles" % label)

	camera.set_bounds(bounds)  # reenquadra (reset_view) com os limites dados
	await process_frame
	var fit := _fit(view, bounds)

	# --- 2) Zoom mínimo: a fase inteira cabe na área jogável -------------
	_set_zoom(camera, camera.zoom_min_effective())
	await process_frame
	var visible := _visible_world_rect(camera, view)
	var bounds_screen := _screen_rect_of(camera, bounds)
	if fit >= GameCamera.ZOOM_MIN - ZOOM_EPS:
		_check(_contains(view, bounds_screen, EPS),
			"%s: fase inteira dentro da área jogável no zoom mínimo (fit=%.3f, zoom=%.3f, view=%s, fase_na_tela=%s)"
			% [label, fit, camera.zoom.x, str(view), str(bounds_screen)])
		_check(bounds_screen.end.x <= controls_rect.position.x + EPS,
			"%s: fase não fica atrás dos controles no zoom mínimo" % label)
	_check(_nested_per_axis(visible, bounds, EPS),
		"%s: visão aninhada nos limites no zoom mínimo (vis=%s, bounds=%s)" % [label, str(visible), str(bounds)])

	# --- 3) Pan até cada borda: a borda correspondente entra na visão ----
	for dir in DIRECTIONS:
		camera.pan_by(dir * PAN_BIG)
		await process_frame
		visible = _visible_world_rect(camera, view)
		_check(_nested_per_axis(visible, bounds, EPS),
			"%s: visão aninhada após pan %s (vis=%s)" % [label, str(dir), str(visible)])
		if dir.x > 0.0:
			_check(visible.end.x >= bounds.end.x - EPS,
				"%s: borda direita da fase entra na área visível (vis.end.x=%.1f, bounds.end.x=%.1f)"
				% [label, visible.end.x, bounds.end.x])
		elif dir.x < 0.0:
			_check(visible.position.x <= bounds.position.x + EPS,
				"%s: borda esquerda da fase entra na área visível (vis.x=%.1f, bounds.x=%.1f)"
				% [label, visible.position.x, bounds.position.x])
		if dir.y > 0.0:
			_check(visible.end.y >= bounds.end.y - EPS,
				"%s: borda inferior da fase entra na área visível (vis.end.y=%.1f, bounds.end.y=%.1f)"
				% [label, visible.end.y, bounds.end.y])
		elif dir.y < 0.0:
			_check(visible.position.y <= bounds.position.y + EPS,
				"%s: borda superior da fase entra na área visível (vis.y=%.1f, bounds.y=%.1f)"
				% [label, visible.position.y, bounds.position.y])

	# --- 4) Reset canhão<->alvo: o enquadramento pega os elementos -------
	var cannon: Cannon = game.cannon
	var target: Target = game.current_target
	if target != null:
		camera.reset_view(cannon.position, target.position)
		await process_frame
		visible = _visible_world_rect(camera, view)
		var middle := (cannon.position + target.position) * 0.5
		_check(visible.grow(EPS).has_point(middle),
			"%s: ponto médio canhão<->alvo visível após reset" % label)
		# Ambos só têm obrigação de caber juntos quando a margem do
		# enquadramento (segmento + RESET_FOCUS_MARGIN) cabe na área — com
		# zoom no piso ZOOM_MIN o enquadramento é limitado e a navegação
		# passa a valer (coberta pelos checks de pan acima).
		var need := Vector2(
			absf(cannon.position.x - target.position.x),
			absf(cannon.position.y - target.position.y)) \
			+ Vector2(GameCamera.RESET_FOCUS_MARGIN, GameCamera.RESET_FOCUS_MARGIN)
		var need_on_screen := need * camera.zoom.x
		if need_on_screen.x <= view.size.x + EPS and need_on_screen.y <= view.size.y + EPS:
			_check(visible.grow(EPS).has_point(cannon.position),
				"%s: canhão visível após reset do enquadramento" % label)
			_check(visible.grow(EPS).has_point(target.position),
				"%s: alvo visível após reset do enquadramento" % label)

	# --- 5) Zoom ancorado (rodinha/pinça): mantém os limites e a faixa ---
	camera.zoom_by_factor_at_screen_point(1.0 / 8.0, view.get_center())
	await _await_zoom(camera)
	await process_frame
	_check(_nested_per_axis(_visible_world_rect(camera, view), bounds, EPS),
		"%s: zoom-out ancorado mantém a visão dentro dos limites" % label)
	camera.zoom_by_factor_at_screen_point(64.0, view.get_center())
	await _await_zoom(camera)
	await process_frame
	visible = _visible_world_rect(camera, view)
	_check(_nested_per_axis(visible, bounds, EPS),
		"%s: zoom-in ancorado mantém a visão dentro dos limites" % label)
	_check(camera.zoom.x >= camera.zoom_min_effective() - ZOOM_EPS
		and camera.zoom.x <= GameCamera.ZOOM_MAX + ZOOM_EPS,
		"%s: zoom dentro da faixa permitida (zoom=%.3f, min=%.3f)"
		% [label, camera.zoom.x, camera.zoom_min_effective()])
	_check(visible.grow(EPS).has_point(bounds.get_center()),
		"%s: centro da fase visível após zoom" % label)


## Instancia a cena real do jogo sob o viewport indicado.
func _instantiate_game(parent: Node) -> Node:
	var packed := load("res://screens/game.tscn") as PackedScene
	var game := packed.instantiate()
	parent.add_child(game)
	return game


## Espera o load_level() assíncrono (build + prewarm) terminar.
func _wait_loaded(game: Node) -> void:
	var tries := 0
	while (bool(game._loading) or bool(game.game_over)) and tries < LOAD_TRIES:
		await physics_frame
		tries += 1
	_check(not bool(game._loading) and not bool(game.game_over), "fase carregada")


## Força zoom instantâneo (o suavizador levaria frames até o alvo).
func _set_zoom(camera: GameCamera, z: float) -> void:
	camera._target_zoom = z  # interno por convenção; o teste fixa o estado final
	camera.zoom = Vector2(z, z)
	camera.apply_bounds_clamp()


func _await_zoom(camera: GameCamera) -> void:
	var tries := 0
	while absf(camera.zoom.x - camera._target_zoom) > 0.0005 and tries < MAX_ZOOM_FRAMES:
		await process_frame
		tries += 1


## Retângulo do mundo que a viewport realmente mostra (verdade absoluta do
## teste: derivado da área do mundo, não do que a câmera declare).
func _visible_world_rect(camera: GameCamera, view: Rect2) -> Rect2:
	var top_left := camera.screen_to_world(view.position)
	var bottom_right := camera.screen_to_world(view.end)
	return Rect2(top_left, bottom_right - top_left)


## Retângulo de tela ocupado por um retângulo de mundo (4 cantos).
func _screen_rect_of(camera: GameCamera, rect: Rect2) -> Rect2:
	var xf := camera.get_canvas_transform()
	var corners: Array[Vector2] = [
		xf * rect.position,
		xf * Vector2(rect.end.x, rect.position.y),
		xf * rect.end,
		xf * Vector2(rect.position.x, rect.end.y),
	]
	var min_v := corners[0]
	var max_v := corners[0]
	for corner in corners:
		min_v = min_v.min(corner)
		max_v = max_v.max(corner)
	return Rect2(min_v, max_v - min_v)


static func _fit(view: Rect2, bounds: Rect2) -> float:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return 1.0
	return minf(view.size.x / bounds.size.x, view.size.y / bounds.size.y)


static func _contains(outer: Rect2, inner: Rect2, eps: float) -> bool:
	return inner.position.x >= outer.position.x - eps \
		and inner.position.y >= outer.position.y - eps \
		and inner.end.x <= outer.end.x + eps \
		and inner.end.y <= outer.end.y + eps


static func _rects_eq(a: Rect2, b: Rect2, eps: float) -> bool:
	return _contains(a, b, eps) and _contains(b, a, eps)


## Por eixo: um retângulo contém o outro (invariante do clamp da câmera).
static func _nested_per_axis(a: Rect2, b: Rect2, eps: float) -> bool:
	return _nested_axis(a.position.x, a.end.x, b.position.x, b.end.x, eps) \
		and _nested_axis(a.position.y, a.end.y, b.position.y, b.end.y, eps)


static func _nested_axis(a0: float, a1: float, b0: float, b1: float, eps: float) -> bool:
	return (a0 <= b0 + eps and a1 >= b1 - eps) or (b0 <= a0 + eps and b1 >= a1 - eps)


func _vp_size(game: Node) -> Vector2:
	return game.game_camera.get_viewport_rect().size


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("CAMERA_VIEW_TEST FALHOU: " + label)
