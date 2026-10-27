class_name Target
extends StaticBody2D
## Alvo da fase — 3 sprites compostos: `base` (estática), `ring` e
## `portal`. Estes dois últimos giram em sentidos opostos de forma
## infinita, direto em `_process(delta)`: mesmo padrão do background
## (background_shapes.gd / floating_shape.gd) — incremental, sem Tween
## e sem reinicialização, então não há pausa perceptível.
## `hit()` é roteado pelo Bullet (bullet.gd:_route_hit) e emite
## `target_hit`, a condição de vitória consumida por game.gd e
## cannon_controller.gd.

signal target_hit(body: Bullet)

## Velocidade angular dos sprites animados (rad/s): 1 volta a cada ~6,3 s.
## Em Godot a rotação positiva é horária, por isso o `ring` (anti-horário)
## subtrai e o `portal` (horário) soma.
const SPIN_SPEED := 1.0

@onready var ring: Sprite2D = $ring
@onready var portal: Sprite2D = $portal


func _process(delta: float) -> void:
	ring.rotation -= SPIN_SPEED * delta
	portal.rotation += SPIN_SPEED * delta


func hit(bullet: Bullet, _impact_position: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(bullet):
		return
	target_hit.emit(bullet)
