class_name GlassShard
extends RigidBody2D

@export var lifetime: float = 3.0


func _ready() -> void:
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()
