extends RigidBody2D

var is_broken: bool = false

@onready var hit_detector: Area2D = $HitDetector

func _ready() -> void:
	hit_detector.body_entered.connect(_on_hit_detector_body_entered)


func _on_hit_detector_body_entered(body: Node) -> void:
	if not body.has_method("hit"):
		return

	body.hit(self)

func del_bullet():
	if is_broken:
		return

	is_broken = true

	queue_free()
