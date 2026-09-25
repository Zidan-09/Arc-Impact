class_name Target
extends Area2D
## Condição de vitória (Etapa 0, docs/plan.md).
## Area2D instanciada por `components/target/target.tscn` com colisor
## retangular 80x80. Emite `hit` quando um Bullet entra na área.
## Shards e outros corpos são ignorados.

signal hit(body: Bullet)


func _ready() -> void:
	add_to_group("target")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Bullet:
		hit.emit(body)


func _draw() -> void:
	# Mira concêntrica desenhada por código (sem assets externos).
	draw_circle(Vector2.ZERO, 40.0, Color(0.85, 0.27, 0.94, 1.0))
	draw_circle(Vector2.ZERO, 28.0, Color(0.05, 0.03, 0.08, 1.0))
	draw_circle(Vector2.ZERO, 16.0, Color(0.13, 0.83, 0.93, 1.0))
	draw_circle(Vector2.ZERO, 6.0, Color(1.0, 1.0, 1.0, 1.0))
