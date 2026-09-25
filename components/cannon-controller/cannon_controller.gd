extends Node2D

@onready var cannon = $Cannon
@onready var power_slider = $PowerSlider
@onready var fire_button: TextureButton = $FireButton

var _dragging_angle := false


func _ready() -> void:
	fire_button.focus_mode = Control.FOCUS_NONE
	fire_button.pressed.connect(shoot)


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
			_dragging_angle = event.pressed
	elif event is InputEventMouseMotion and _dragging_angle:
		cannon.rotate_cannon(-event.relative.y)
	elif event is InputEventScreenTouch:
		if event.index == 0:
			_dragging_angle = event.pressed
	elif event is InputEventScreenDrag:
		if event.index == 0 and _dragging_angle:
			cannon.rotate_cannon(-event.relative.y)


func shoot() -> void:
	cannon.shoot(power_slider.power)
