extends StaticBody2D

var is_broken: bool = false

@onready var sprite = $Sprite
@onready var hitBox = $HitBox

func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pass

func break_glass() -> void:
	if is_broken:
		return

	is_broken = true

	hitBox.set_deferred("disabled", true)

	sprite.hide()

	queue_free()
