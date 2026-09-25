class_name GlassObstacle
extends Obstacle

@export_range(0.0, 1.0) var velocity_retain: float = 0.85

var is_broken: bool = false

@onready var sprite: Sprite2D = $Sprite
@onready var hit_box: Area2D = $HitBox


func _ready() -> void:
	super._ready()
	hit_box.body_entered.connect(_on_hit_box_body_entered)


func _on_hit_box_body_entered(body: Node2D) -> void:
	if is_broken:
		return
	if body is RigidBody2D:
		hit(body)


func on_hit_started(bullet: RigidBody2D) -> void:
	if is_instance_valid(bullet):
		bullet.linear_velocity *= velocity_retain
	hit_box.set_deferred("monitoring", false)


func on_hit_completed(_bullet: RigidBody2D) -> void:
	shatter()


func shatter() -> void:
	if is_broken:
		return
	is_broken = true
	sprite.hide()
	queue_free()
