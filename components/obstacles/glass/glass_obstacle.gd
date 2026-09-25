class_name GlassObstacle
extends Obstacle

@export_range(0.0, 1.0) var velocity_retain: float = 0.85

@export var shard_count: int = 5
@export var shard_min_speed: float = 150.0
@export var shard_max_speed: float = 400.0
@export var shard_spread: float = 0.5
@export var shard_min_angular_velocity: float = -10.0
@export var shard_max_angular_velocity: float = 10.0

@export var shard_scene: PackedScene

const SHARD_SCENE_FALLBACK := preload("res://components/obstacles/glass/glass_shard.tscn")

var is_broken: bool = false

@onready var sprite: Sprite2D = $Sprite
@onready var hit_box: Area2D = $HitBox


func _ready() -> void:
	super._ready()
	hit_box.body_entered.connect(_on_hit_box_body_entered)


func _on_hit_box_body_entered(body: Node2D) -> void:
	if is_broken or is_processing_hit:
		return
	if body is GlassShard:
		return
	if body is StoneShard:
		return
	if body is RigidBody2D:
		hit(body, body.global_position)


func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
	if is_broken or is_processing_hit:
		return
	if bullet is GlassShard:
		return
	if bullet is StoneShard:
		return
	if not is_instance_valid(bullet):
		return

	is_processing_hit = true
	is_broken = true

	if impact_position == Vector2.INF:
		impact_position = bullet.global_position

	var shatter_velocity := bullet.linear_velocity
	bullet.linear_velocity *= velocity_retain
	hit_box.set_deferred("monitoring", false)

	if shatter_velocity != Vector2.ZERO:
		_spawn_shards(shatter_velocity, impact_position)

	sprite.hide()
	queue_free()


func on_hit_started(_bullet: RigidBody2D) -> void:
	pass


func on_hit_completed(_bullet: RigidBody2D, _impact_position: Vector2) -> void:
	pass


func _spawn_shards(shatter_velocity: Vector2, impact_position: Vector2) -> void:
	var impact_direction := shatter_velocity.normalized()
	var explosion_direction := impact_direction
	var bullet_speed := shatter_velocity.length()
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	var sprite_rect := sprite.get_rect()
	var spawn_extents := sprite_rect.size * 0.5 * global_scale * 0.5
	var scene := shard_scene if shard_scene != null else SHARD_SCENE_FALLBACK
	for i in shard_count:
		var shard := scene.instantiate() as RigidBody2D
		parent.add_child(shard)
		var spawn_offset := Vector2(
			randf_range(-spawn_extents.x, spawn_extents.x),
			randf_range(-spawn_extents.y, spawn_extents.y)
		)
		shard.global_position = impact_position + spawn_offset
		shard.global_rotation = randf() * TAU
		var direction := explosion_direction.rotated(
			randf_range(-shard_spread, shard_spread)
		)
		var shard_speed := bullet_speed * randf_range(0.3, 0.7)
		shard_speed = clampf(shard_speed, shard_min_speed, shard_max_speed)
		shard.linear_velocity = direction * shard_speed
		shard.angular_velocity = randf_range(
			shard_min_angular_velocity,
			shard_max_angular_velocity
		)
