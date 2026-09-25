class_name StoneObstacle
extends Obstacle

@onready var crackedTexture = $CrackedStone
@onready var polishedTexture = $PolishedStone

@onready var stoneLife := 2.0

func _ready() -> void:
	super._ready()
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 1.0
	physics_material_override = mat
	
	crackedTexture.visible = false

func on_hit_completed(_bullet: RigidBody2D, _impact_position: Vector2) -> void:
	stoneLife -= 1
	
	if stoneLife == 1:
		crackedTexture.visible = true
		polishedTexture.visible = false
	
	if stoneLife == 0:
		queue_free()
