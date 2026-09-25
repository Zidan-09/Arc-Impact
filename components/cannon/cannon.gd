extends Node2D

@export_range(-20.0, 90.0, 1.0)
var min_angle: float = -20.0

@export_range(-45.0, 83.0, 1.0)
var max_angle: float = 83.0

@export
var rotation_sensitivity: float = 0.5

@export var bullet_scene: PackedScene

@onready var barrel_pivot: Node2D = $BarrelPivot
@onready var muzzle: Marker2D = $BarrelPivot/Muzzle

var current_angle: float = 45.0
var dragging: bool = false


func _ready() -> void:
	update_cannon_rotation()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_SPACE and event.pressed:
			shoot()
			
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed

	elif event is InputEventMouseMotion and dragging:
		rotate_cannon(-event.relative.y)

	elif event is InputEventScreenTouch:
		if event.index == 0:
			dragging = event.pressed

	elif event is InputEventScreenDrag and dragging:
		rotate_cannon(-event.relative.y)


func rotate_cannon(delta_y: float) -> void:
	current_angle += delta_y * rotation_sensitivity

	current_angle = clampf(
		current_angle,
		min_angle,
		max_angle
	)

	update_cannon_rotation()


func update_cannon_rotation() -> void:
	barrel_pivot.rotation_degrees = -current_angle

func shoot() -> void:
	var bullet := bullet_scene.instantiate()

	get_tree().current_scene.add_child(bullet)

	bullet.global_position = muzzle.global_position

	var direction := Vector2.RIGHT.rotated(muzzle.global_rotation)

	bullet.linear_velocity = direction * 1000.0
