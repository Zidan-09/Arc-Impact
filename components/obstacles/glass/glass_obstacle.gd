class_name GlassObstacle
extends Obstacle

@export_range(0.0, 1.0) var velocity_retain: float = 0.85

var is_broken: bool = false

@onready var sprite: Sprite2D = $Sprite
@onready var hit_box: CollisionShape2D = $HitBox


func _ready() -> void:
	super._ready()


func on_hit_started(_bullet: RigidBody2D) -> void:
	hit_box.set_deferred("disabled", true)


func on_hit_completed(bullet: RigidBody2D) -> void:
	shatter(bullet)


func shatter(bullet: RigidBody2D) -> void:
	if is_broken:
		return
	is_broken = true
	if is_instance_valid(bullet):
		bullet.linear_velocity *= velocity_retain
	sprite.hide()
	queue_free()
