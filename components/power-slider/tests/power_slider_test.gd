extends SceneTree
## Slider de força com 10 níveis discretos (components/power-slider).
## Critérios:
##  1. exatamente 10 níveis; a seleção é sempre um inteiro 1..10 e
##     NUNCA um valor intermediário (nem na propriedade `power`, nem no
##     sinal `power_changed`);
##  2. snap: arraste menor que meio-passo mantém o nível, arraste além
##     dele move exatamente 1 nível; arraste grande clampa nos extremos;
##  3. força proporcional ao nível entre min_power (0.3) e max_power
##     (1.0), com nível 1 = 0.3 e nível 10 = 1.0 exatos;
##  4. o indicador ocupa 10 posições distintas do track (uma por nível);
##  5. mouse (botão + motion) e touch (ScreenTouch + ScreenDrag) percorrem
##     os mesmos caminhos de entrada e produzem o mesmo snap; o arrasto
##     continua suave (o delta não é quantizado) e a seleção final é
##     sempre um dos 10 níveis.
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/power-slider/tests/power_slider_test.gd
## Saída: "POWER_SLIDER_TEST: PASS" (exit 0) ou FAIL (exit 1).

const SLIDER_SCENE: PackedScene = preload("res://components/power-slider/powerSlider.tscn")
const POWER_LEVELS := 10
const MIN_POWER := 0.3
const MAX_POWER := 1.0
const SENSITIVITY := 0.0012   # power_slider.gd @export sensitivity
const EPS := 0.000001
## Ponto do track usado pelos eventos sintéticos (retângulo global do
## Track: (-96,-72)-(98,646), com o slider em (0,0)).
const TRACK_POINT := Vector2(50, 300)
## Passo do arraste em px: 25 * 0.0012 = 0.03 de força < meio-passo
## (0.0389), então cada passo move no máximo 1 nível.
const SWEEP_STEP_PX := 25.0

var _failures := 0
var _emitted: Array[float] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	# A janela headless nasce em 64x64 com content-scale 0.05 (o jogo roda
	# em 1280x720, escala 1:1). Igualar o tamanho aqui mantém o hit-test
	# do GUI e os deltas de arraste em coordenadas de canvas 1:1 — as
	# mesmas condições do jogo real — para os eventos sintéticos abaixo
	# percorrerem o pipeline de input de ponta a ponta.
	root.size = Vector2i(1280, 720)
	await process_frame
	_check(root.get_screen_transform() == Transform2D.IDENTITY,
		"pré-condição: viewport em escala 1:1 (%s)" % str(root.get_screen_transform()))

	var slider = SLIDER_SCENE.instantiate()
	root.add_child(slider)
	await process_frame # _ready do slider (@onready resolvidos)

	slider.power_changed.connect(_on_power_changed)

	_case_initial(slider)
	_case_ten_levels(slider)
	_case_snap(slider)
	_case_sweep(slider)
	_case_extremes(slider)
	_case_mouse(slider)
	_case_touch(slider)
	_case_emissions()

	slider.queue_free()
	if _failures == 0:
		print("POWER_SLIDER_TEST: PASS")
	else:
		printerr("POWER_SLIDER_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


## Estado inicial: nível 1 com a força mínima (mesmo valor do slider
## livre anterior: 0.3).
func _case_initial(slider) -> void:
	_check(slider.power_level == 1, "inicial: nível 1 (obtido %d)" % slider.power_level)
	_check(is_equal_approx(slider.power, MIN_POWER),
		"inicial: força mínima %.4f" % slider.power)


## Os 10 níveis, um a um: seleção inteira, força proporcional entre os
## extremos e indicador na posição discreta correspondente.
func _case_ten_levels(slider) -> void:
	var handle_positions: Array[float] = []
	for level in range(1, POWER_LEVELS + 1):
		slider.set_level(level)
		var expected := _expected_power(level)
		_check(slider.power_level == level,
			"nível %d: seleção inteira (obtido %d)" % [level, slider.power_level])
		_check(is_equal_approx(slider.power, expected),
			"nível %d: força proporcional %.6f (obtido %.6f)" % [level, expected, slider.power])
		_check(absf(slider.power - expected) <= EPS,
			"nível %d: sem valor intermediário" % level)
		_check(absf(slider.handle.position.y - _expected_handle_y(slider, level)) <= 0.01,
			"nível %d: indicador na posição discreta (y=%.2f)" % [
				level, slider.handle.position.y])
		_check(absf(slider.power_gradient.position.y - slider.handle.position.y) <= 0.01,
			"nível %d: gradiente acompanha o indicador" % level)
		handle_positions.append(slider.handle.position.y)

	_check(_distinct_count(handle_positions) == POWER_LEVELS,
		"indicador ocupa %d posições distintas (esperado %d)" % [
			_distinct_count(handle_positions), POWER_LEVELS])

	# Clamp de set_level com valores fora da faixa.
	slider.set_level(0)
	_check(slider.power_level == 1 and is_equal_approx(slider.power, MIN_POWER),
		"set_level(0) => nível 1 / força mínima")
	slider.set_level(99)
	_check(slider.power_level == POWER_LEVELS and is_equal_approx(slider.power, MAX_POWER),
		"set_level(99) => nível 10 / força máxima")
	slider.set_level(1)


## Snap: meio-passo para cima/baixo em torno do nível 1.
func _case_snap(slider) -> void:
	slider.set_level(1)
	# meio-passo em força = (max-min) / (2*(niveis-1))
	var half_step := (MAX_POWER - MIN_POWER) / (2.0 * float(POWER_LEVELS - 1))
	var px := half_step / SENSITIVITY

	# Logo ABAIXO do meio do passo: continua no nível 1.
	slider.update_power(px - 2.0)
	_check(slider.power_level == 1,
		"snap: arraste de %.1fpx (< meio-passo) mantém o nível 1 (obtido %d)" % [
			px - 2.0, slider.power_level])
	_check(is_equal_approx(slider.power, MIN_POWER),
		"snap: força continua exatamente a mínima")

	# Passa do meio: encaixa no nível 2, sem valores intermediários.
	slider.update_power(4.0)
	_check(slider.power_level == 2,
		"snap: arraste além do meio-passo encaixa no nível 2 (obtido %d)" % slider.power_level)
	_check(is_equal_approx(slider.power, _expected_power(2)),
		"snap: força do nível 2 (%.6f)" % slider.power)

	# Volta para baixo do meio do passo: retorna ao nível 1 (sem deriva).
	slider.update_power(-4.0)
	_check(slider.power_level == 1,
		"snap: retorno abaixo do meio-passo volta ao nível 1 (obtido %d)" % slider.power_level)

	# power_to_level: vizinhos do limiar entre níveis 1 e 2.
	var midpoint := (_expected_power(1) + _expected_power(2)) / 2.0
	_check(slider.power_to_level(midpoint - EPS * 10.0) == 1,
		"snap: força logo abaixo do limiar => nível 1")
	_check(slider.power_to_level(midpoint + EPS * 10.0) == 2,
		"snap: força logo acima do limiar => nível 2")
	_check(slider.power_to_level(MIN_POWER) == 1, "snap: força mínima => nível 1")
	_check(slider.power_to_level(MAX_POWER) == POWER_LEVELS,
		"snap: força máxima => nível %d" % POWER_LEVELS)


## Varredura contínua (subida e descida) em passos pequenos: os 10
## níveis são visitados em ordem, sem pular e sem nunca observar um
## valor intermediário.
func _case_sweep(slider) -> void:
	slider.set_level(1)
	var visited := {}
	for i in range(40):
		slider.update_power(SWEEP_STEP_PX)
		visited[slider.power_level] = true
		_assert_invariant(slider, "sweep subida %d" % i, true)
	_check(slider.power_level == POWER_LEVELS,
		"sweep: alcance do nível 10 no topo (obtido %d)" % slider.power_level)

	for i in range(40):
		slider.update_power(-SWEEP_STEP_PX)
		visited[slider.power_level] = true
		_assert_invariant(slider, "sweep descida %d" % i, true)
	_check(slider.power_level == 1,
		"sweep: volta ao nível 1 na base (obtido %d)" % slider.power_level)
	_check(visited.size() == POWER_LEVELS,
		"sweep: os 10 níveis foram visitados (visitei %d)" % visited.size())

	# Percorrido aleatório determinístico: qualquer trajetória de arraste
	# termina sempre num dos 10 níveis.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	slider.set_level(5)
	for i in range(2000):
		slider.update_power(rng.randf_range(-60.0, 60.0))
		_assert_invariant(slider, "walk %d" % i, true)
	_check(slider.power_level >= 1 and slider.power_level <= POWER_LEVELS,
		"walk: seleção final sempre dentro dos 10 níveis (obtido %d)" % slider.power_level)
	slider.set_level(1)


## Extremos: as forças mínima/máxima anteriores (0.3 e 1.0) preservadas,
## mesmo arrastando muito além dos limites.
func _case_extremes(slider) -> void:
	slider.set_level(1)
	slider.update_power(-100000.0)
	_check(slider.power_level == 1, "extremo inferior: nível 1 (obtido %d)" % slider.power_level)
	_check(is_equal_approx(slider.power, MIN_POWER),
		"extremo inferior: força mínima %.4f (esperada %.4f)" % [slider.power, MIN_POWER])

	slider.set_level(POWER_LEVELS)
	slider.update_power(100000.0)
	_check(slider.power_level == POWER_LEVELS,
		"extremo superior: nível %d (obtido %d)" % [POWER_LEVELS, slider.power_level])
	_check(is_equal_approx(slider.power, MAX_POWER),
		"extremo superior: força máxima %.4f (esperada %.4f)" % [slider.power, MAX_POWER])
	slider.set_level(1)


## Mouse: press no Track inicia o drag, motion arrasta com snap, release
## encerra preservando a seleção.
func _case_mouse(slider) -> void:
	slider.set_level(1)
	get_root().push_input(_mouse_button(true, TRACK_POINT))
	_check(slider.dragging, "mouse: press no Track inicia o drag")

	get_root().push_input(_mouse_motion(TRACK_POINT, Vector2(0, -40)))
	_check(slider.power_level == 2,
		"mouse: arraste de 40px encaixa no nível 2 (obtido %d)" % slider.power_level)
	_assert_invariant(slider, "mouse após motion")

	get_root().push_input(_mouse_button(false, TRACK_POINT))
	_check(not slider.dragging, "mouse: release encerra o drag")
	_check(slider.power_level == 2,
		"mouse: nível preservado após o release (obtido %d)" % slider.power_level)

	# Movimento para baixo reduz a força até o nível 1.
	get_root().push_input(_mouse_button(true, TRACK_POINT))
	get_root().push_input(_mouse_motion(TRACK_POINT, Vector2(0, 60)))
	_check(slider.power_level == 1,
		"mouse: arraste para baixo volta ao nível 1 (obtido %d)" % slider.power_level)
	get_root().push_input(_mouse_button(false, TRACK_POINT))
	_check(not slider.dragging, "mouse: segundo release encerra o drag")

	# Arraste em MUITOS eventos pequenos (típico de mouse: eventos de
	# 1-2px): a soma dos deltas precisa atravessar o meio do passo.
	# Regressão do snap que resnappava o acumulador a cada evento e
	# travava o slider no nível atual.
	slider.set_level(1)
	get_root().push_input(_mouse_button(true, TRACK_POINT))
	for i in range(60):
		get_root().push_input(_mouse_motion(TRACK_POINT, Vector2(0, -2)))
		_assert_invariant(slider, "mouse micro-passos %d" % i, true)
	_check(slider.power_level == 3,
		"mouse: 60 motion events de 2px acumulam até o nível 3 (obtido %d)" %
			slider.power_level)
	get_root().push_input(_mouse_button(false, TRACK_POINT))
	_check(not slider.dragging, "mouse: release encerra o drag de micro-passos")
	slider.set_level(1)


## Touch: ScreenTouch pressa o Track, ScreenDrag (dedo 0) arrasta com o
## mesmo snap; o dedo 1 é ignorado; release encerra.
func _case_touch(slider) -> void:
	slider.set_level(1)
	get_root().push_input(_touch(0, true, TRACK_POINT))
	_check(slider.dragging, "touch: press no Track inicia o drag")

	get_root().push_input(_drag(0, TRACK_POINT, Vector2(0, -40)))
	_check(slider.power_level == 2,
		"touch: arraste de 40px encaixa no nível 2 (obtido %d)" % slider.power_level)
	_assert_invariant(slider, "touch após drag")

	# Segundo dedo não pode mexer na força.
	get_root().push_input(_drag(1, TRACK_POINT, Vector2(0, -400)))
	_check(slider.power_level == 2,
		"touch: drag do dedo 1 é ignorado (nível %d)" % slider.power_level)

	get_root().push_input(_touch(0, false, TRACK_POINT))
	_check(not slider.dragging, "touch: release encerra o drag")
	_check(slider.power_level == 2,
		"touch: nível preservado após o release (obtido %d)" % slider.power_level)
	slider.set_level(1)


## O sinal power_changed só pode ter emitido valores entre os 10 níveis.
func _case_emissions() -> void:
	_check(not _emitted.is_empty(), "sinal power_changed emitiu valores")
	var intermediate := 0
	for value in _emitted:
		if not _is_level_power(value):
			intermediate += 1
			printerr("  [FAIL] emissão intermediária: %s" % str(value))
	_check(intermediate == 0,
		"todas as %d emissões correspondem a um dos 10 níveis (%d intermediárias)" % [
			_emitted.size(), intermediate])


func _assert_invariant(slider, ctx: String, quiet: bool = false) -> void:
	_check(slider.power_level >= 1 and slider.power_level <= POWER_LEVELS,
		"%s => nível %d dentro de 1..%d" % [ctx, slider.power_level, POWER_LEVELS], quiet)
	_check(_is_level_power(slider.power),
		"%s => força %s é um dos 10 níveis" % [ctx, str(slider.power)], quiet)
	_check(slider.power >= MIN_POWER - EPS and slider.power <= MAX_POWER + EPS,
		"%s => força %.6f dentro de [%.4f, %.4f]" % [
			ctx, slider.power, MIN_POWER, MAX_POWER], quiet)


func _on_power_changed(value: float) -> void:
	_emitted.append(value)


## Força esperada do nível — MESMA fórmula de power_slider.level_to_power
## (lerpf(min, max, (nivel-1)/(niveis-1))), reescrita aqui de propósito:
## o teste confere a implementação, não a repete cegamente.
func _expected_power(level: int) -> float:
	return lerpf(MIN_POWER, MAX_POWER, float(level - 1) / float(POWER_LEVELS - 1))


func _is_level_power(value: float) -> bool:
	for level in range(1, POWER_LEVELS + 1):
		if absf(value - _expected_power(level)) <= EPS:
			return true
	return false


## Posição Y esperada do indicador para o nível (mesmo mapeamento
## discreto de power_slider.update_handle_position).
func _expected_handle_y(slider, level: int) -> float:
	var limits: Vector2 = slider.get_handle_limits()
	return lerpf(limits.y, limits.x, float(level - 1) / float(POWER_LEVELS - 1))


func _distinct_count(values: Array[float]) -> int:
	var seen := {}
	for value in values:
		seen[round(value * 1000.0)] = true
	return seen.size()


func _mouse_button(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pos
	event.global_position = pos
	return event


func _mouse_motion(pos: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	event.relative = relative
	return event


func _touch(index: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	return event


func _drag(index: int, pos: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	return event


func _check(cond: bool, msg: String, quiet: bool = false) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	elif not quiet:
		print("  [ok] " + msg)
