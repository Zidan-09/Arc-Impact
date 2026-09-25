class_name Bullet
extends RigidBody2D
## Projétil do canhão — notas de física (Etapa 0, docs/plan.md):
## - Corpo: CircleShape2D raio 46.173584; HitDetector: Area2D raio 56.0
##   (valores-base em `bullet.tscn`; `apply_cannon_scale()` os reescala
##   por instância sem mutar o recurso compartilhado).
## - collision_layer/mask: defaults (1/1). Colide fisicamente com
##   StaticBody2D (metal/pedra, paredes do cano) e detecta logicamente
##   via HitDetector -> `Obstacle.hit()`.
## - Vidro usa Area2D atravessável (atenua *= 0.85 em vez de rebater);
##   ver `glass_obstacle.gd`. Shards são ignorados pelos obstáculos.

var is_broken: bool = false

# Bases capturadas na primeira chamada (valores do bullet.tscn).
# Guardadas para que apply_cannon_scale() nunca acumule fator.
var _base_body_radius: float = -1.0
var _base_detector_radius: float = -1.0
var _base_sprite_scale: Vector2 = Vector2.ZERO

@onready var hit_detector: Area2D = $HitDetector

func _ready() -> void:
	hit_detector.body_entered.connect(_on_hit_detector_body_entered)


## Ajusta o tamanho do bullet na mesma proporção do canhão.
## Por que explícito e não só `bullet.scale = ...`?
## Escalar um RigidBody2D via node.scale nem sempre propaga para a
## física (o servidor de física pode manter o raio original do
## CircleShape2D), então o visual encolhia mas a colisão continuava
## grande — e o bullet não saía do cano. Aqui o raio é alterado de
## fato (em shapes duplicados por instância) mais o sprite.
## Massa e velocidade NÃO mudam: só geometria + visual.
func apply_cannon_scale(cannon_global_scale: Vector2) -> void:
	var factor := cannon_global_scale.x
	if absf(cannon_global_scale.x - cannon_global_scale.y) > 0.0001:
		push_warning(
			"Bullet.apply_cannon_scale: escala não-uniforme %s; usando x como fator." % str(cannon_global_scale)
		)

	if _base_body_radius < 0.0:
		# Lê os valores atuais (instância recém-criada == valores do .tscn).
		_base_body_radius = (($CollisionShape2D as CollisionShape2D).shape as CircleShape2D).radius
		_base_detector_radius = (($HitDetector/CollisionShape2D as CollisionShape2D).shape as CircleShape2D).radius
		_base_sprite_scale = ($Sprite2D as Sprite2D).scale

	# Duplica os shapes: o sub_resource do PackedScene é compartilhado
	# entre instâncias; sem duplicate() todas as balas seriam afetadas.
	var body_col := $CollisionShape2D as CollisionShape2D
	var body_circle := (body_col.shape as CircleShape2D).duplicate() as CircleShape2D
	body_circle.radius = _base_body_radius * factor
	body_col.shape = body_circle

	var detector_col := $HitDetector/CollisionShape2D as CollisionShape2D
	var detector_circle := (detector_col.shape as CircleShape2D).duplicate() as CircleShape2D
	detector_circle.radius = _base_detector_radius * factor
	detector_col.shape = detector_circle

	($Sprite2D as Sprite2D).scale = _base_sprite_scale * factor


func _on_hit_detector_body_entered(body: Node) -> void:
	if is_broken:
		return
	if not body.has_method("hit"):
		return

	body.hit(self, global_position)

func del_bullet():
	if is_broken:
		return

	is_broken = true

	queue_free()
