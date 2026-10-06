class_name Bullet
extends RigidBody2D
## Projétil do canhão — fonte única de verdade (docs/plan.md §5 item 2):
## - Corpo: CircleShape2D raio 57.717 (valor-base em `bullet.tscn`;
##   x escala canônica 0.16 do canhão = ~9.2px, o calibre calibrado;
##   `apply_cannon_scale()` o reescala por instância sem mutar o recurso).
## - collision_layer/mask: defaults (1/1). Colide fisicamente com
##   StaticBody2D (metal/pedra, paredes do cano, floor, corpo do alvo).
## - Lógica de gameplay (`Obstacle.hit()`, `Target.hit()`) roteada AQUI:
##   `body_entered` do corpo + varredura `intersect_ray` do segmento
##   prev→current com `collide_with_areas = true` (alcança o `HitBox`
##   Area2D do vidro mesmo quando o tick pula o collider fino).
## - Deduplicação por instância: o primeiro hit por corpo vale; o resto
##   é ignorado (idempotência soma com `is_processing_hit`/`is_broken`).
## - Vidro usa Area2D atravessável (atenua *= 0.85 em vez de rebater);
##   ver `glass_obstacle.gd`. Shards são ignorados pelos obstáculos.

var is_broken: bool = false

# Base capturada na primeira chamada (valor do bullet.tscn).
# Guardada para que apply_cannon_scale() nunca acumule fator.
var _base_body_radius: float = -1.0
var _base_sprite_scale: Vector2 = Vector2.ZERO

# Varredura prev→current (item 2). Teleporte de spawn (>120px/frame)
# só realinha o cursor, sem raycast (evita falso positivo do add_child
# antes do posicionamento no muzzle — ver cannon.gd:shoot()).
var _prev_position: Vector2 = Vector2.INF
const TELEPORT_DIST := 120.0
const SWEEP_MAX_STEPS := 8

# Instâncias já roteadas (corpo e/ou Area2D do vidro).
var _notified_ids := {}

var trail: BulletTrail


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_prev_position = global_position
	trail = BulletTrail.new()
	trail.follow_target = self
	trail.add_to_group("bullet_trails")
	get_parent().add_child(trail)


## Ajusta o tamanho do bullet na mesma proporção do canhão.
## Por que explícito e não só `bullet.scale = ...`?
## Escalar um RigidBody2D via node.scale nem sempre propaga para a
## física (o servidor de física pode manter o raio original do
## CircleShape2D), então o visual encolhia mas a colisão continuava
## grande — e o bullet não saía do cano. Aqui o raio é alterado de
## fato (em shape duplicado por instância) mais o sprite.
## Massa e velocidade NÃO mudam: só geometria + visual.
func apply_cannon_scale(cannon_global_scale: Vector2) -> void:
	var factor := cannon_global_scale.x
	if absf(cannon_global_scale.x - cannon_global_scale.y) > 0.0001:
		push_warning(
			"Bullet.apply_cannon_scale: escala não-uniforme %s; usando x como fator." % str(cannon_global_scale)
		)

	if _base_body_radius < 0.0:
		# Lê o valor atual (instância recém-criada == valor do .tscn).
		_base_body_radius = (($CollisionShape2D as CollisionShape2D).shape as CircleShape2D).radius
		_base_sprite_scale = ($Sprite2D as Sprite2D).scale

	# Duplica o shape: o sub_resource do PackedScene é compartilhado
	# entre instâncias; sem duplicate() todas as balas seriam afetadas.
	var body_col := $CollisionShape2D as CollisionShape2D
	var body_circle := (body_col.shape as CircleShape2D).duplicate() as CircleShape2D
	body_circle.radius = _base_body_radius * factor
	body_col.shape = body_circle

	($Sprite2D as Sprite2D).scale = _base_sprite_scale * factor


func _physics_process(_delta: float) -> void:
	if is_broken:
		return
	if _prev_position == Vector2.INF:
		_prev_position = global_position
		return
	var current := global_position
	var dist := _prev_position.distance_to(current)
	if dist < 0.01:
		return
	if dist > TELEPORT_DIST:
		# Spawn/teleporte: realinha sem varrer (posição do _ready é
		# anterior ao posicionamento no muzzle).
		_prev_position = current
		return
	_swept_check(_prev_position, current)
	_prev_position = current


## Varredura do segmento varrido no tick: enxerga bodies E areas
## (HitBox do vidro). Roteia o primeiro hit novo; vidro atravessável
## continua a varredura no mesmo segmento (pode haver alvo atrás).
func _swept_check(from: Vector2, to: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	var exclude: Array[RID] = [get_rid()]
	for _i in SWEEP_MAX_STEPS:
		var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, exclude)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit.get("collider")
		var pos: Vector2 = hit.get("position", to)
		if collider == null:
			break
		if not (collider is Node):
			break
		var node := collider as Node
		var id := node.get_instance_id()
		if _notified_ids.has(id):
			_exclude_collider(exclude, node)
			continue
		_notified_ids[id] = true
		var routed := _route_hit(node, pos)
		if not routed:
			# Chão/parede sem hit(): física resolve; nada a rotear.
			break
		if is_broken:
			break
		if node is Area2D:
			# Vidro: atravessa com *= 0.85 — segue varrendo o resto
			# do segmento no mesmo tick (alvo atrás do vidro conta).
			_exclude_collider(exclude, node)
			continue
		# Sólido (pedra/metal/alvo): física rebate; encerra o tick.
		break


func _exclude_collider(exclude: Array[RID], node: Node) -> void:
	if node is CollisionObject2D:
		var rid := (node as CollisionObject2D).get_rid()
		if not exclude.has(rid):
			exclude.append(rid)


## Roteador único de gameplay. Retorna true se houve hit de gameplay.
func _route_hit(node: Node, pos: Vector2) -> bool:
	if is_broken or not is_instance_valid(self):
		return false
	if node is Shard:
		return false
	if node.has_method("hit"):
		node.call("hit", self, pos)
		return true
	if node is Area2D:
		# HitBox do vidro: o Area2D não tem hit(), o pai tem.
		var parent := node.get_parent()
		if parent != null and parent.has_method("hit"):
			_notified_ids[parent.get_instance_id()] = true
			parent.call("hit", self, pos)
			return true
	return false


func _on_body_entered(body: Node) -> void:
	if is_broken:
		return
	if body == null or not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	if _notified_ids.has(id):
		return
	_notified_ids[id] = true
	_route_hit(body, global_position)


func del_bullet():
	if is_broken:
		return

	is_broken = true

	queue_free()
