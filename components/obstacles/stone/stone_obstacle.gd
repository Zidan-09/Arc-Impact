class_name StoneObstacle
extends Obstacle

@export_range(0.0, 1.0) var velocity_retain: float = 0.85

@export var shard_count: int = 5
@export var shard_min_speed: float = 150.0
@export var shard_max_speed: float = 400.0
@export var shard_spread: float = 0.5
@export var shard_min_angular_velocity: float = -10.0
@export var shard_max_angular_velocity: float = 10.0

@export var shard_scene: PackedScene

const SHARD_SCENE_FALLBACK := preload("res://components/obstacles/stone/stone_shard.tscn")

@onready var crackedTexture = $CrackedStone
@onready var polishedTexture = $PolishedStone
@onready var hit_box: CollisionShape2D = $HitBox

var stoneLife := 2
var is_destroyed := false

func _ready() -> void:
	super._ready()
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 1.0
	physics_material_override = mat

	crackedTexture.visible = false

func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
	if is_destroyed:
		return
	if bullet is Shard:
		return
	if stoneLife <= 1:
		if not is_instance_valid(bullet):
			return
		is_destroyed = true

		if impact_position == Vector2.INF:
			impact_position = bullet.global_position

		var shatter_velocity := bullet.linear_velocity
		var retained := shatter_velocity * velocity_retain
		bullet.linear_velocity = retained
		hit_box.set_deferred("disabled", true)

		if shatter_velocity != Vector2.ZERO:
			_spawn_shards(shatter_velocity, impact_position)

		crackedTexture.hide()
		polishedTexture.hide()

		await get_tree().physics_frame
		await get_tree().physics_frame
		if is_instance_valid(bullet):
			bullet.linear_velocity = retained
		if is_instance_valid(self):
			queue_free()
		return
	super.hit(bullet, impact_position)

func on_hit_started(_bullet: RigidBody2D) -> void:
	if stoneLife == 2:
		crackedTexture.visible = true
		polishedTexture.visible = false


func on_hit_completed(_bullet: RigidBody2D, _impact_position: Vector2) -> void:
	stoneLife -= 1

	if stoneLife <= 1:
		crackedTexture.visible = true
		polishedTexture.visible = false

	if stoneLife <= 0:
		queue_free()


func _spawn_shards(shatter_velocity: Vector2, impact_position: Vector2) -> void:
	var to_center := global_position - impact_position
	var explosion_direction: Vector2
	if to_center.length() > 1.0:
		explosion_direction = to_center.normalized()
	else:
		explosion_direction = shatter_velocity.normalized()
	var bullet_speed := shatter_velocity.length()
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	var sprite_rect: Rect2 = crackedTexture.get_rect()
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
