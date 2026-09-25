extends Area2D

func _ready() -> void:
	body_entered.connect(_on_bullet_return_detector_body_entered)

func _on_bullet_return_detector_body_entered(body: Node2D) -> void:
	if not body.has_method("del_bullet"):
		return
		
	body.del_bullet()
