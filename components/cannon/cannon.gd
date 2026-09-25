extends Node2D

@export_range(-20.0, 90.0, 1.0)
var min_angle: float = -20.0

@export_range(-45.0, 83.0, 1.0)
var max_angle: float = 83.0

@export
var rotation_sensitivity: float = 0.5

@export var bullet_scene: PackedScene

@export var base_shot_speed: float = 1000.0

@onready var barrel_pivot: Node2D = $BarrelPivot
@onready var muzzle: Marker2D = $BarrelPivot/Muzzle

var current_angle: float = 45.0


func _ready() -> void:
	update_cannon_rotation()


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

func shoot(power: float = 1.0) -> void:
	if bullet_scene == null:
		push_warning("Cannon.shoot() sem bullet_scene definida.")
		return

	var bullet := bullet_scene.instantiate() as RigidBody2D

	get_tree().current_scene.add_child(bullet)

	bullet.global_position = muzzle.global_position

	var direction := Vector2.RIGHT.rotated(muzzle.global_rotation)

	bullet.linear_velocity = direction * base_shot_speed * clampf(power, 0.0, 1.0)
