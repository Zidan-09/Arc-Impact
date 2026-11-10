extends Control
## Nó de fase do mapa de progresso (tela Levels).
##
## Desenha o círculo, o número da fase e o estado visual:
## - DONE: fase já concluída (ciano + check) — jogável de novo;
## - CURRENT: fase atual/disponível (magenta + pulso + tag "ATUAL");
## - LOCKED: fase bloqueada (cinza + cadeado) — nunca inicia.
##
## Ativação só ocorre quando pressionar e soltar ficam próximos em
## coordenadas de canvas: um arrasto para rolar o mapa que começa sobre
## um nó não dispara a fase (o nó entrega o evento ao ScrollContainer
## via `mouse_filter = PASS`).

signal activated(level: int)
signal blocked(level: int)

enum State { DONE, CURRENT, LOCKED }

const FONT := preload("res://assets/fonts/PressStart2P-Regular.ttf")

## Distância máxima (canvas) entre pressionar e soltar para contar
## como ativação da fase.
const ACTIVATION_DRAG := 24.0
## Ganho de tamanho no hover (destaque de "clicável").
const HOVER_GROW := 3.0

const DONE_FILL := Color(0.133, 0.827, 0.933, 0.16)
const DONE_LINE := Color(0.133, 0.827, 0.933, 0.95)
const DONE_TEXT := Color(0.92, 0.99, 1.0, 1.0)
const CURRENT_FILL := Color(0.851, 0.275, 0.937, 0.3)
const CURRENT_LINE := Color(0.851, 0.275, 0.937, 1.0)
const CURRENT_TEXT := Color(1.0, 1.0, 1.0, 1.0)
const LOCKED_FILL := Color(0.07, 0.05, 0.12, 0.6)
const LOCKED_LINE := Color(0.392, 0.455, 0.545, 0.6)
const LOCKED_TEXT := Color(0.47, 0.53, 0.62, 0.95)
const LOCK_GLYPH := Color(0.66, 0.72, 0.8, 0.95)

var level := 1
var state: int = State.LOCKED

var _pressing := false
var _hovered := false
var _press_canvas := Vector2.ZERO


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## Reconfigura o nó para uma fase. Chamado pelo mapa a cada criação ou
## reutilização do pool.
func setup(new_level: int, new_state: int) -> void:
	level = new_level
	state = new_state
	# PASS: o arrasto/toque continua subindo até o ScrollContainer,
	# permitindo rolar o mapa começando sobre um nó.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_pressing = false
	# Reutilização do pool: o nó pode ter saído da tela ainda "hovered".
	_hovered = false
	# Só o nó atual anima; os demais não gastam frame em _process.
	set_process(state == State.CURRENT)
	queue_redraw()


## Apenas o nó atual pulsa (anel expandindo). Chamado todo frame.
func _process(_delta: float) -> void:
	if state == State.CURRENT:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if state == State.LOCKED:
		# Bloqueada: só avisa a tela (nunca ativa a fase).
		if mouse.pressed:
			blocked.emit(level)
		return
	if mouse.pressed:
		_pressing = true
		_press_canvas = _to_canvas(mouse.position)
		queue_redraw()
		return
	if not _pressing:
		return
	_pressing = false
	queue_redraw()
	var moved := _to_canvas(mouse.position).distance_to(_press_canvas)
	if moved <= ACTIVATION_DRAG and Rect2(Vector2.ZERO, size).has_point(mouse.position):
		activated.emit(level)


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	if _pressing:
		_pressing = false
		queue_redraw()


## Posição do evento em coordenadas de canvas: imune ao scroll que
## acontece entre pressionar e soltar (o nó acompanha o movimento).
func _to_canvas(local_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * local_pos


func _draw() -> void:
	var c := size * 0.5
	var r := size.x * 0.5 - 14.0
	var grow := 0.0
	if state != State.LOCKED:
		grow = HOVER_GROW if _hovered else 0.0
		if _pressing:
			r *= 0.93
			grow = 0.0
	match state:
		State.DONE:
			_paint(c, r, grow, DONE_FILL, DONE_LINE, 3.0)
		State.CURRENT:
			_paint(c, r, grow, CURRENT_FILL, CURRENT_LINE, 4.0)
			_draw_pulse(c, r)
		State.LOCKED:
			_paint(c, r, 0.0, LOCKED_FILL, LOCKED_LINE, 3.0)
			_draw_lock(c, r)
	_draw_number(c)
	if state == State.CURRENT:
		_draw_current_tag(c)


func _paint(c: Vector2, r: float, grow: float, fill: Color, line: Color, width: float) -> void:
	var radius := r + grow
	# Halo neon (disco um pouco maior e bem transparente, depois o
	# preenchimento por cima) — mesmo efeito de brilho do popup.
	draw_circle(c, radius + 7.0, Color(fill.r, fill.g, fill.b, fill.a * 0.45))
	draw_circle(c, radius, fill)
	draw_arc(c, radius, 0.0, TAU, 56, line, width, true)


func _draw_pulse(c: Vector2, r: float) -> void:
	var wave := (sin(Time.get_ticks_msec() * TAU / 1000.0) + 1.0) * 0.5
	var radius := r + 6.0 + wave * 7.0
	var alpha := 0.5 - wave * 0.3
	draw_arc(c, radius, 0.0, TAU, 56, Color(CURRENT_LINE.r, CURRENT_LINE.g, CURRENT_LINE.b, alpha), 2.0, true)


func _draw_lock(c: Vector2, r: float) -> void:
	var p := c + Vector2(r * 0.7, -r * 0.62)
	draw_rect(Rect2(p + Vector2(-7.0, -4.0), Vector2(14.0, 11.0)), LOCK_GLYPH, true)
	draw_arc(p + Vector2(0.0, -4.0), 4.5, PI, TAU, 20, LOCK_GLYPH, 2.0, true)
	draw_circle(p + Vector2(0.0, 1.5), 2.0, LOCKED_FILL)


func _draw_number(c: Vector2) -> void:
	var text := str(level)
	var fs := _font_size(text.length())
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var color := DONE_TEXT
	match state:
		State.CURRENT:
			color = CURRENT_TEXT
		State.LOCKED:
			color = LOCKED_TEXT
	# Press Start 2P tem ascendente == tamanho e descendente 0: a baseline
	# fica em centro + tamanho/2 para centralizar verticalmente.
	draw_string(
		FONT,
		Vector2(c.x - w * 0.5, c.y + fs * 0.5),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		color
	)


func _draw_current_tag(c: Vector2) -> void:
	var text := "ATUAL"
	var fs := 9
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(
		FONT,
		Vector2(c.x - w * 0.5, 10.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		CURRENT_LINE
	)


## Tamanho da fonte por quantidade de dígitos (Press Start 2P é
## monoespaçado: 1 caractere = 1 unidade de tamanho), mantendo o número
## dentro do disco em qualquer magnitude de fase.
static func _font_size(digits: int) -> int:
	if digits <= 2:
		return 20
	if digits == 3:
		return 17
	if digits == 4:
		return 15
	if digits == 5:
		return 12
	return 10
