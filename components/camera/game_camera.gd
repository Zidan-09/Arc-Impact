class_name GameCamera
extends Camera2D
## Câmera de exploração da fase (docs/plan.md §§3-8 + §16).
## Filha de `WorldArea/World` em `screens/game.tscn`: o pan/zoom afetam só o
## canvas padrão (mundo). HUD e painéis vivem em `UILayer` (CanvasLayer) e o
## fundo estático em `BackgroundLayer` (CanvasLayer) — ambos imunes à câmera.
## Limites dinâmicos via `set_bounds()` (fonte: `LevelDefinition.world_bounds`);
## nunca hard-coda 1280x720 — usa `get_viewport_rect().size` (aspect = expand).
## O zoom mínimo é dinâmico: nunca mostra além da fase inteira (sem vazio).
## Física, geração, validação e solver não referenciam esta câmera.

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 1.1
const ZOOM_SMOOTH_SPEED := 10.0
const KEYBOARD_PAN_SPEED := 600.0
const RESET_FOCUS_MARGIN := 200.0
const DEFAULT_BOUNDS := Rect2(0, 0, 1280, 720)

var bounds: Rect2 = DEFAULT_BOUNDS

var _target_zoom := 1.0
var _has_anchor := false
var _anchor_screen := Vector2.ZERO


func _ready() -> void:
	enabled = true
	make_current()
	_target_zoom = zoom.x
	apply_bounds_clamp()


func _process(delta: float) -> void:
	_update_smooth_zoom(delta)
	_update_keyboard_pan(delta)


## Define os limites da fase e reenquadra (chamado por `game.gd` em `load_level()`).
func set_bounds(new_bounds: Rect2) -> void:
	if new_bounds.size.x <= 0.0 or new_bounds.size.y <= 0.0:
		push_warning("GameCamera.set_bounds: Rect2 inválido %s; mantendo %s." % [str(new_bounds), str(bounds)])
		return
	bounds = new_bounds
	reset_view()


## Volta ao enquadramento inicial: zoom 1 (ou fit se os focos excederem a
## visão), posição no ponto médio dos focos ou no centro dos limites.
func reset_view(focus_a: Vector2 = Vector2.INF, focus_b: Vector2 = Vector2.INF) -> void:
	_has_anchor = false
	var center := bounds.get_center()
	var has_a := focus_a.x != INF
	var has_b := focus_b.x != INF
	if has_a and has_b:
		center = (focus_a + focus_b) * 0.5
	elif has_a:
		center = focus_a
	_target_zoom = 1.0
	if has_a and has_b:
		var fit := _zoom_to_fit_segment(focus_a, focus_b)
		if fit < 1.0:
			_target_zoom = fit
	zoom = Vector2(_target_zoom, _target_zoom)
	position = center
	apply_bounds_clamp()


## Zoom necessário para exibir os limites inteiros (clampado à faixa útil).
func fit_to_bounds() -> float:
	return clampf(fit_zoom_raw(), ZOOM_MIN, ZOOM_MAX)


## Fit sem clamp: base do zoom mínimo dinâmico.
func fit_zoom_raw() -> float:
	var viewport_size := get_viewport_rect().size
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return 1.0
	return minf(viewport_size.x / bounds.size.x, viewport_size.y / bounds.size.y)


## Zoom mínimo efetivo: o maior entre o piso absoluto e o fit da fase.
## Numa fase do tamanho da viewport resulta 1.0 (nada além para revelar);
## numa fase 2x maior, 0.5. Impede o "vazio" que o zoom-out fixo causava.
func zoom_min_effective() -> float:
	return clampf(fit_zoom_raw(), ZOOM_MIN, 1.0)


## Reaplica o clamp (chamar em resize da janela / `size_changed` do viewport).
## Se a janela cresceu e o zoom atual ficou abaixo do novo mínimo, eleva o
## alvo (a suavização em `_process` conduz o zoom até lá).
func refresh() -> void:
	_target_zoom = maxf(_target_zoom, zoom_min_effective())
	if zoom.x < _target_zoom and not _has_anchor:
		zoom = Vector2(_target_zoom, _target_zoom)
	apply_bounds_clamp()


## Move a câmera por um delta em pixels de tela (sensação 1:1 "agarrar o mundo").
func pan_by(screen_delta: Vector2) -> void:
	_has_anchor = false
	position += screen_delta / _target_zoom
	apply_bounds_clamp()


## Zoom imediato no alvo (atualiza o zoom desejado); a âncora no cursor é
## resolvida de forma suave em `_process()` (ordem: zoom -> âncora -> clamp).
func zoom_by_factor_at_screen_point(factor: float, screen_point: Vector2) -> void:
	var clamped := clampf(_target_zoom * factor, zoom_min_effective(), ZOOM_MAX)
	if is_equal_approx(clamped, _target_zoom):
		return
	_anchor_screen = screen_point
	_has_anchor = true
	_target_zoom = clamped


func zoom_step_in() -> void:
	zoom_by_factor_at_screen_point(ZOOM_STEP, get_viewport().get_mouse_position())


func zoom_step_out() -> void:
	zoom_by_factor_at_screen_point(1.0 / ZOOM_STEP, get_viewport().get_mouse_position())


func screen_to_world(screen_point: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_point


## Clamp manual (docs/plan.md §8.2): não usa `Camera2D.limit_*`, que não
## recentraliza quando a visão excede os limites e briga com zoom animado.
## Contenção ESTRITA: a área visível da viewport nunca sai da área da
## fase. `bounds` vem da grade gerada (`LevelDefinition.world_bounds` =
## `GridState.phase_bounds()`), logo é dinâmico por fase. Se a viewport
## for maior que a fase num eixo (zoom-out além do fit é barrado por
## `zoom_min_effective()`, mas resize pode causar), a câmera centraliza
## naquele eixo em vez de permitir navegação para o vazio.
func apply_bounds_clamp() -> void:
	var viewport_size := get_viewport_rect().size
	var half_view := viewport_size * 0.5 / zoom.x
	position = Vector2(
		_clamp_axis(position.x, bounds.position.x, bounds.end.x, half_view.x, bounds.get_center().x),
		_clamp_axis(position.y, bounds.position.y, bounds.end.y, half_view.y, bounds.get_center().y))


static func _clamp_axis(center: float, bounds_min: float, bounds_max: float, half_view: float, bounds_center: float) -> float:
	if bounds_max - bounds_min >= half_view * 2.0:
		return clampf(center, bounds_min + half_view, bounds_max - half_view)
	return bounds_center


func _update_smooth_zoom(delta: float) -> void:
	var old_zoom := zoom.x
	var weight := 1.0 - exp(-ZOOM_SMOOTH_SPEED * delta)
	var new_zoom := lerpf(old_zoom, _target_zoom, weight)
	if is_equal_approx(new_zoom, old_zoom):
		if is_equal_approx(new_zoom, _target_zoom):
			zoom = Vector2(_target_zoom, _target_zoom)
			_has_anchor = false
		return
	if _has_anchor:
		var before := screen_to_world(_anchor_screen)
		zoom = Vector2(new_zoom, new_zoom)
		var after := screen_to_world(_anchor_screen)
		position += before - after
		_has_anchor = not is_equal_approx(new_zoom, _target_zoom)
		if not _has_anchor:
			zoom = Vector2(_target_zoom, _target_zoom)
	else:
		zoom = Vector2(new_zoom, new_zoom)
	apply_bounds_clamp()


func _update_keyboard_pan(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		direction.y += 1.0
	if direction == Vector2.ZERO:
		return
	_has_anchor = false
	position += direction.normalized() * KEYBOARD_PAN_SPEED / _target_zoom * delta
	apply_bounds_clamp()


func _zoom_to_fit_segment(from: Vector2, to: Vector2) -> float:
	var viewport_size := get_viewport_rect().size
	var need := Vector2(absf(to.x - from.x), absf(to.y - from.y)) + Vector2(RESET_FOCUS_MARGIN, RESET_FOCUS_MARGIN)
	if need.x <= 0.0 or need.y <= 0.0:
		return 1.0
	var fit := minf(viewport_size.x / need.x, viewport_size.y / need.y)
	return clampf(fit, zoom_min_effective(), 1.0)
