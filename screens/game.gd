extends Control

const END_DELAY := 8.0
const DEFAULT_SEED := 1

@onready var world_area: Control = $WorldArea
@onready var world: Node2D = $WorldArea/World
@onready var level_node: Node2D = $WorldArea/World/Level
@onready var cannon: Cannon = $WorldArea/World/Cannon
@onready var game_camera: GameCamera = $WorldArea/World/GameCamera
@onready var world_hit_area: Control = $UILayer/WorldHitArea
@onready var hud = $UILayer/Hud
@onready var power_slider = $UILayer/Hud/Controls/PowerSlider
@onready var fire_button: TextureButton = $UILayer/Hud/Controls/FireButton
@onready var victory_popup = $UILayer/LevelCompletePopup

var builder: LevelBuilder
var current_def: LevelDefinition = null
var current_target: Target = null
var level_number := 1
var current_seed := DEFAULT_SEED
var ammo_total := 0
var ammo_left := 0
var game_over := true
var won := false

var _loading := false
var _awaiting_end := false
var _end_timer := 0.0
var _is_paused := false
var _dragging_angle := false
var _panning := false
# Toques ativos (index -> posição) para pan/pinça com 2 dedos.
var _touch_points: Dictionary = {}
var _has_touch_centroid := false
var _last_touch_centroid := Vector2.ZERO
var _last_pinch_distance := 0.0


func _ready() -> void:
	fire_button.focus_mode = Control.FOCUS_NONE
	fire_button.pressed.connect(shoot)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	cannon.bullet_container = level_node
	cannon.current_power = power_slider.power
	power_slider.power_changed.connect(_on_power_changed)
	victory_popup.home_pressed.connect(_on_popup_home)
	victory_popup.retry_pressed.connect(_on_popup_retry)
	victory_popup.next_pressed.connect(_on_popup_next)
	victory_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.pause_pressed.connect(_on_pause_pressed)
	builder = LevelBuilder.new()
	add_child(builder)
	load_level(DEFAULT_SEED, level_number)


func load_level(seed_value: int, new_level_number: int) -> void:
	if _loading:
		return
	_loading = true
	_is_paused = false
	get_tree().paused = false
	game_over = true
	won = false
	_awaiting_end = false
	_end_timer = 0.0
	ammo_total = 0
	ammo_left = 0
	current_def = null
	current_target = null
	level_number = new_level_number
	current_seed = seed_value
	victory_popup.visible = false
	for bullet in get_tree().get_nodes_in_group("bullets"):
		bullet.queue_free()
	var result := FastLevelGenerator.generate(seed_value, level_number)
	var def: LevelDefinition = result["def"]
	if bool(result["fallback_used"]):
		push_warning("Game: fallback usado (%s)." % str(result["log"]))
	var built := await builder.build(level_node, def)
	current_def = def
	cannon.position = def.cannon_position
	ammo_total = def.ammo
	ammo_left = def.ammo
	current_target = built["target"] as Target
	if current_target != null:
		current_target.target_hit.connect(_on_target_hit)
	_update_camera_bounds()
	game_over = false
	_loading = false
	hud.set_level(level_number)
	hud.set_ammo(ammo_total, ammo_left)


func shoot() -> void:
	if game_over or _loading or _is_paused:
		return
	if ammo_left <= 0:
		return
	ammo_left -= 1
	cannon.shoot(power_slider.power)
	_end_timer = 0.0
	_awaiting_end = ammo_left <= 0
	hud.set_ammo(ammo_total, ammo_left)


func _physics_process(delta: float) -> void:
	if not _awaiting_end or won or game_over:
		return
	_end_timer += delta
	var bullets := get_tree().get_nodes_in_group("bullets")
	if bullets.is_empty() or _end_timer >= END_DELAY:
		_defeat()


func _on_target_hit(_body: Bullet) -> void:
	if game_over or won:
		return
	won = true
	game_over = true
	_awaiting_end = false
	victory_popup.show_popup(0, ammo_left)


func _defeat() -> void:
	game_over = true
	_awaiting_end = false
	victory_popup.show_defeat_popup(0, ammo_left)


func _on_power_changed(value: float) -> void:
	cannon.set_power(value)


func _on_popup_home() -> void:
	_is_paused = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://screens/home.tscn")


func _on_popup_retry() -> void:
	_is_paused = false
	get_tree().paused = false
	load_level(current_seed, level_number)


func _on_popup_next() -> void:
	if _is_paused:
		resume_game()
		return
	load_level(current_seed + 1, level_number + 1)


func _on_pause_pressed() -> void:
	if _loading or _is_paused:
		return
	if game_over or won:
		return
	if victory_popup.visible:
		return
	_is_paused = true
	get_tree().paused = true
	victory_popup.show_pause_popup(0, ammo_left)


func resume_game() -> void:
	if not _is_paused:
		return
	_is_paused = false
	victory_popup.visible = false
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if _is_paused:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging_angle = false
		elif (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE) and not event.pressed:
			_panning = false
	elif event is InputEventScreenTouch:
		if not event.pressed:
			_touch_points.erase(event.index)
			if _touch_points.size() < 2:
				_has_touch_centroid = false
				_last_pinch_distance = 0.0
			if event.index == 0:
				_dragging_angle = false


func _unhandled_input(event: InputEvent) -> void:
	if _is_paused:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_angle = event.pressed and _press_in_world(event.position)
			if event.pressed and _dragging_angle:
				_panning = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			game_camera.zoom_step_in()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			game_camera.zoom_step_out()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			# Pan: botão esquerdo segue exclusivo da mira (§6). Pan e mira
			# nunca ficam ativos ao mesmo tempo.
			if event.pressed and _press_in_world(event.position):
				if event.double_click:
					_reset_camera_view()
				else:
					_panning = true
					_dragging_angle = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and (_panning or _dragging_angle):
		if _panning:
			game_camera.pan_by(-event.relative)
		else:
			cannon.rotate_cannon(-event.relative.y)
	elif event is InputEventScreenTouch:
		if event.index == 0:
			_dragging_angle = event.pressed and _press_in_world(event.position)
			if event.pressed:
				_touch_points[event.index] = event.position
				if _dragging_angle:
					_cancel_touch_camera()
		else:
			if event.pressed:
				# Segundo dedo: sai da mira e entra em modo câmera (pan/pinça).
				_touch_points[event.index] = event.position
				_dragging_angle = false
				_begin_touch_camera()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _touch_points.has(event.index) and _touch_points.size() >= 2:
			_touch_points[event.index] = event.position
			_update_touch_camera()
		elif event.index == 0 and _dragging_angle:
			cannon.rotate_cannon(-event.relative.y)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			game_camera.zoom_step_in()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			game_camera.zoom_step_out()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_reset_camera_view()
			get_viewport().set_input_as_handled()


## Região jogável em coordenadas de viewport. Usa `WorldHitArea`, um Control
## invisível dentro de `UILayer` (CanvasLayer, imune à câmera) com a mesma
## geometria do `WorldArea`. O `WorldArea` não serve para isso: por estar no
## canvas padrão, seu `get_global_transform_with_canvas()` inclui a câmera e
## o teste derivaria junto com o pan/zoom.
func _press_in_world(viewport_pos: Vector2) -> bool:
	var local: Vector2 = world_hit_area.get_global_transform_with_canvas().affine_inverse() * viewport_pos
	return Rect2(Vector2.ZERO, world_hit_area.size).has_point(local)


## Centroide dos toques ativos (modo câmera com 2 dedos).
func _touch_centroid() -> Vector2:
	var sum := Vector2.ZERO
	for key in _touch_points:
		sum += _touch_points[key] as Vector2
	return sum / float(maxi(_touch_points.size(), 1))


func _begin_touch_camera() -> void:
	if _touch_points.size() < 2:
		return
	_last_touch_centroid = _touch_centroid()
	_has_touch_centroid = true
	_last_pinch_distance = _touch_span()


func _cancel_touch_camera() -> void:
	_has_touch_centroid = false
	_last_pinch_distance = 0.0


func _update_touch_camera() -> void:
	if _touch_points.size() < 2:
		return
	var centroid := _touch_centroid()
	if _has_touch_centroid:
		game_camera.pan_by(-(centroid - _last_touch_centroid))
	_last_touch_centroid = centroid
	_has_touch_centroid = true
	# Pinça: zoom relativo ancorado no centroide (ordem: zoom -> âncora -> clamp,
	# resolvida dentro de `zoom_by_factor_at_screen_point` + `_process`).
	var span := _touch_span()
	if _last_pinch_distance > 0.0 and span > 0.0:
		game_camera.zoom_by_factor_at_screen_point(span / _last_pinch_distance, centroid)
	_last_pinch_distance = span


## Distância entre os dois primeiros toques (span da pinça).
func _touch_span() -> float:
	var keys := _touch_points.keys()
	if keys.size() < 2:
		return 0.0
	return (_touch_points[keys[0]] as Vector2).distance_to(_touch_points[keys[1]] as Vector2)


## Informa à câmera os limites da fase atual e reenquadra no ponto médio
## canhão↔alvo (docs/plan.md §10). Fallback para `play_bounds` em defs
## antigas/degeneradas.
func _update_camera_bounds() -> void:
	if not is_instance_valid(game_camera) or current_def == null:
		return
	var bounds := current_def.world_bounds
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		bounds = current_def.play_bounds
	game_camera.set_bounds(bounds)
	_reset_camera_view()


## Volta ao enquadramento inicial canhão↔alvo (tecla R, duplo-clique com
## botão direito, toda troca de fase).
func _reset_camera_view() -> void:
	if not is_instance_valid(game_camera):
		return
	if current_target != null:
		game_camera.reset_view(cannon.position, current_target.position)
	elif current_def != null:
		game_camera.reset_view(cannon.position)
	else:
		game_camera.reset_view()


func _on_viewport_size_changed() -> void:
	if is_instance_valid(game_camera):
		game_camera.refresh()
