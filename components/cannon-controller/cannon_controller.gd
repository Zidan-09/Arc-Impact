extends Node2D

@onready var cannon = $Cannon
@onready var power_slider = $PowerSlider

var _dragging_angle := false


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_SPACE and event.pressed and not event.echo:
			shoot()
		return

	# Safety: soltura sempre destrava, mesmo se soltar em cima do slider
	# (nesse caso o release é consumido pela UI e não chega ao _unhandled_input).
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging_angle = false
	elif event is InputEventScreenTouch:
		if event.index == 0 and not event.pressed:
			_dragging_angle = false


func _unhandled_input(event: InputEvent) -> void:
	# Só chega aqui o que a UI (Track/Handle do PowerSlider) NÃO consumiu,
	# ou seja: qualquer outra área da tela -> ângulo do Cannon.
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
