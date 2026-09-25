extends RigidBody2D

var is_broken: bool = false

@export_range(0.0, 1.0) var glass_impact_loss: float = 0.25

@onready var hit_detector: Area2D = $HitDetector

var hit_glass: bool = false

func _ready() -> void:
	hit_detector.body_entered.connect(_on_hit_detector_body_entered)


func _on_hit_detector_body_entered(body: Node) -> void:
	if hit_glass:
		return

	if not body.has_method("break_glass"):
		return

	hit_glass = true

	linear_velocity *= (1.0 - glass_impact_loss)

	body.break_glass()

func del_bullet():
	if is_broken:
		return
		
	is_broken = true
	
	queue_free()
