class_name MetalObstacle
extends Obstacle

@export_range(0.0, 1.0) var velocity_retain: float = 0.95
@export var min_ricochet_speed: float = 800.0

var _incoming_velocity: Vector2


func _ready() -> void:
	super._ready()


func on_hit_started(bullet: RigidBody2D) -> void:
	_incoming_velocity = bullet.linear_velocity


func on_hit_completed(bullet: RigidBody2D) -> void:
	if not is_instance_valid(bullet):
		return
	var normal := bullet.global_position - global_position
	if normal.length() < 1.0:
		normal = -_incoming_velocity.normalized()
	normal = normal.normalized()
	if normal == Vector2.ZERO:
		return
	var reflected := _incoming_velocity.bounce(normal) * velocity_retain
	if reflected.length() < min_ricochet_speed:
		reflected = reflected.normalized() * min_ricochet_speed
	bullet.linear_velocity = reflected
