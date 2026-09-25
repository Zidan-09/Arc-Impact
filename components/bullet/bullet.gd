extends RigidBody2D

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

	# Reduz a velocidade antes de continuar.
	linear_velocity *= (1.0 - glass_impact_loss)

	# Quebra o vidro.
	body.break_glass()
