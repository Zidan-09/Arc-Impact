class_name StoneObstacle
extends Obstacle

@export_range(0.0, 1.0) var velocity_retain: float = 0.85

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
	if bullet is GlassShard:
		return
	if stoneLife <= 1:
		if not is_instance_valid(bullet):
			return
		is_destroyed = true
		bullet.linear_velocity *= velocity_retain
		hit_box.set_deferred("disabled", true)
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
