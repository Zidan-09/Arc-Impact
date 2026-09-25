class_name MetalObstacle
extends Obstacle


func _ready() -> void:
	super._ready()
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 1.0
	physics_material_override = mat


func on_hit_completed(_bullet: RigidBody2D) -> void:
	pass
