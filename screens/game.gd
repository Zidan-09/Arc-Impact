extends Control

const END_DELAY := 8.0
const DEFAULT_SEED := 1

@onready var world_area: Control = $WorldArea
@onready var world: Node2D = $WorldArea/World
@onready var level_node: Node2D = $WorldArea/World/Level
@onready var cannon: Cannon = $WorldArea/World/Cannon
@onready var hud = $Hud
@onready var power_slider = $Hud/Controls/PowerSlider
@onready var fire_button: TextureButton = $Hud/Controls/FireButton
@onready var victory_popup = $LevelCompletePopup

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
var _dragging_angle := false


func _ready() -> void:
	fire_button.focus_mode = Control.FOCUS_NONE
	fire_button.pressed.connect(shoot)
	cannon.bullet_container = level_node
	cannon.current_power = power_slider.power
	power_slider.power_changed.connect(_on_power_changed)
	victory_popup.home_pressed.connect(_on_popup_home)
	victory_popup.retry_pressed.connect(_on_popup_retry)
	victory_popup.next_pressed.connect(_on_popup_next)
	builder = LevelBuilder.new()
	add_child(builder)
	load_level(DEFAULT_SEED, level_number)


func load_level(seed_value: int, new_level_number: int) -> void:
	if _loading:
		return
	_loading = true
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
		current_target.hit.connect(_on_target_hit)
	game_over = false
	_loading = false
	hud.set_level(level_number)
	hud.set_ammo(ammo_total, ammo_left)


func shoot() -> void:
	if game_over or _loading:
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
	get_tree().change_scene_to_file("res://screens/home.tscn")


func _on_popup_retry() -> void:
	load_level(current_seed, level_number)


func _on_popup_next() -> void:
	load_level(current_seed + 1, level_number + 1)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging_angle = false
	elif event is InputEventScreenTouch:
		if event.index == 0 and not event.pressed:
			_dragging_angle = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_angle = event.pressed and _press_in_world(event.position)
	elif event is InputEventMouseMotion and _dragging_angle:
		cannon.rotate_cannon(-event.relative.y)
	elif event is InputEventScreenTouch:
		if event.index == 0:
			_dragging_angle = event.pressed and _press_in_world(event.position)
	elif event is InputEventScreenDrag:
		if event.index == 0 and _dragging_angle:
			cannon.rotate_cannon(-event.relative.y)


func _press_in_world(viewport_pos: Vector2) -> bool:
	var local: Vector2 = world_area.get_global_transform_with_canvas().affine_inverse() * viewport_pos
	return Rect2(Vector2.ZERO, world_area.size).has_point(local)
