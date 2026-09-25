class_name Obstacle
extends StaticBody2D

@export_range(1.0, 1.5, 0.01)
var hit_scale: float = 1.08

@export_range(0.05, 0.5, 0.01)
var hit_duration: float = 0.15

var original_scale: Vector2
var is_processing_hit: bool = false


func _ready() -> void:
	original_scale = scale


func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
	if is_processing_hit or not is_instance_valid(bullet):
		return

	is_processing_hit = true

	if impact_position == Vector2.INF:
		impact_position = global_position

	on_hit_started(bullet)

	await play_hit_animation()

	if not is_instance_valid(self):
		return

	# O bullet pode ter sido liberado (queue_free via del_bullet, por exemplo
	# ao atingir o bullet_return_detector) durante o await da animação.
	# Passar uma instância liberada para um parâmetro tipado causa:
	# "Invalid type... (previously freed) is not a subclass...".
	# Por isso revalidamos aqui. null é um valor válido para o parâmetro
	# tipado; as implementações de on_hit_completed ignoram o bullet.
	var live_bullet: RigidBody2D = bullet if is_instance_valid(bullet) else null

	on_hit_completed(live_bullet, impact_position)

	is_processing_hit = false


func on_hit_started(_bullet: RigidBody2D) -> void:
	pass

func play_hit_animation() -> void:
	scale = original_scale

	var tween := create_tween()

	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		self,
		"scale",
		original_scale * hit_scale,
		hit_duration
	)

	tween.tween_property(
		self,
		"scale",
		original_scale,
		hit_duration
	)

	await tween.finished

	scale = original_scale


func on_hit_completed(_bullet: RigidBody2D, _impact_position: Vector2) -> void:
	push_error(
		"on_hit_completed() must be implemented by a child class."
	)
