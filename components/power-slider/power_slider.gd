extends Control

@onready var handle: Control = $Handle
@onready var normal: TextureRect = $Handle/Normal
@onready var pressed: TextureRect = $Handle/Pressed

@export var min_power: float = 0.3
@export var max_power: float = 1.0

@onready var track: TextureRect = $Track

@export_range(0.0001, 0.01, 0.0001)
var sensitivity: float = 0.0012

var dragging := false
var power: float = 0.3

func _ready() -> void:
	update_visual()
	update_handle_position()


func set_dragging(value: bool) -> void:
	dragging = value
	update_visual()


func update_visual() -> void:
	normal.visible = not dragging
	pressed.visible = dragging


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			set_dragging(event.pressed)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and dragging:
		update_power(-event.relative.y)


func update_power(delta: float) -> void:
	power += delta * sensitivity
	power = clampf(power, min_power, max_power)

	update_handle_position()


func update_handle_position() -> void:
	var t := inverse_lerp(min_power, max_power, power)

	var limits := get_handle_limits()

	handle.position.y = lerpf(
		limits.y,
		limits.x,
		t
	)

func get_handle_limits() -> Vector2:
	var half_handle_height := handle.size.y / 2.0

	var top := track.position.y + half_handle_height
	var bottom := track.position.y + track.size.y - half_handle_height - 120

	return Vector2(top, bottom)
