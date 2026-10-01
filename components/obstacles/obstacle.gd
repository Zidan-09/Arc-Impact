class_name Obstacle
extends StaticBody2D

@export_range(1.0, 1.5, 0.01)
var hit_scale: float = 1.08

@export_range(0.05, 0.5, 0.01)
var hit_duration: float = 0.15

var original_scale: Vector2
var is_processing_hit: bool = false

# Escalas-base dos sprites filhos (docs/plan.md §5 item 4): o feedback
# visual pulsa SÓ aqui — a raiz (StaticBody2D) fica fixa para o
# collider não pulsar junto com o visual durante o tween.
var _visual_base_scales := {}


func _ready() -> void:
	original_scale = scale
	_visual_base_scales.clear()
	for child in get_children():
		if child is Sprite2D:
			_visual_base_scales[child] = (child as Sprite2D).scale


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
	# Collider estável: a raiz nunca escala durante o feedback.
	scale = original_scale
	if _visual_base_scales.is_empty():
		await get_tree().create_timer(hit_duration * 2.0).timeout
		return

	var tweens: Array[Tween] = []
	for node in _visual_base_scales.keys():
		if not is_instance_valid(node):
			continue
		var base: Vector2 = _visual_base_scales[node]
		(node as Node2D).scale = base
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(
			node,
			"scale",
			base * hit_scale,
			hit_duration
		)
		tween.tween_property(
			node,
			"scale",
			base,
			hit_duration
		)
		tweens.append(tween)

	if tweens.is_empty():
		return
	await tweens[0].finished

	for node in _visual_base_scales.keys():
		if is_instance_valid(node):
			(node as Node2D).scale = _visual_base_scales[node]
	scale = original_scale


func on_hit_completed(_bullet: RigidBody2D, _impact_position: Vector2) -> void:
	push_error(
		"on_hit_completed() must be implemented by a child class."
	)
