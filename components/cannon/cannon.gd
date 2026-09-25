extends Node2D

@export_range(-20.0, 90.0, 1.0)
var min_angle: float = -20.0

@export_range(-45.0, 83.0, 1.0)
var max_angle: float = 83.0

@export
var rotation_sensitivity: float = 0.5

@export var bullet_scene: PackedScene

@export var base_shot_speed: float = 2000.0

@onready var barrel_pivot: Node2D = $BarrelPivot
@onready var muzzle: Marker2D = $BarrelPivot/Muzzle

var recoil_tween: Tween
var barrel_initial_position: Vector2

const RECOIL_DISTANCE := 25.0
const RECOIL_BACK_TIME := 0.06
const RECOIL_RETURN_TIME := 0.12

var current_angle: float = 45.0

func _ready() -> void:
	barrel_initial_position = barrel_pivot.position
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
	
	play_recoil()

	var bullet := bullet_scene.instantiate() as RigidBody2D

	get_tree().current_scene.add_child(bullet)

	bullet.global_position = muzzle.global_position

	var direction := Vector2.RIGHT.rotated(muzzle.global_rotation)

	bullet.linear_velocity = direction * base_shot_speed * clampf(power, 0.0, 1.0)

func play_recoil() -> void:
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()

	barrel_pivot.position = barrel_initial_position

	# Direção do cano no espaço global.
	var forward_direction := Vector2.RIGHT.rotated(
		barrel_pivot.global_rotation
	).normalized()

	# Recuo no sentido oposto ao disparo.
	var recoil_global_position := barrel_pivot.global_position - (
		forward_direction * RECOIL_DISTANCE
	)

	# Converte para posição local do pai.
	var recoil_position := barrel_pivot.to_global(
		barrel_pivot.position
	)

	recoil_position = barrel_pivot.get_parent().to_local(
		recoil_global_position
	)

	recoil_tween = create_tween()

	recoil_tween.tween_property(
		barrel_pivot,
		"position",
		recoil_position,
		RECOIL_BACK_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	recoil_tween.tween_property(
		barrel_pivot,
		"position",
		barrel_initial_position,
		RECOIL_RETURN_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
