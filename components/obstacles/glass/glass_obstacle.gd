class_name GlassObstacle
extends Obstacle

@export_range(0.0, 1.0) var velocity_retain: float = 0.85

@export var shard_count: int = 5
@export var shard_min_speed: float = 150.0
@export var shard_max_speed: float = 400.0
@export var shard_spread: float = 0.5
@export var shard_min_angular_velocity: float = -10.0
@export var shard_max_angular_velocity: float = 10.0

## Um shard por sprite: cada cena usa um dos fragmentos individuais
## (glass_shard_1..5.png). `shard_count` limita quantos são instanciados
## (0 desliga — usado pelo SimulationWorld, que zera para a simulação).
@export var shard_scenes: Array[PackedScene] = []

const SHARD_SCENES_FALLBACK: Array[PackedScene] = [
	preload("res://components/obstacles/glass/glass_shard_1.tscn"),
	preload("res://components/obstacles/glass/glass_shard_2.tscn"),
	preload("res://components/obstacles/glass/glass_shard_3.tscn"),
	preload("res://components/obstacles/glass/glass_shard_4.tscn"),
	preload("res://components/obstacles/glass/glass_shard_5.tscn"),
]

## Escala do Sprite2D authorada nas cenas glass_shard_N. No spawn ela é
## remapeada para a escala global do vidro quebrado (0.1 no gate, 0.05
## nos postes): como os PNGs têm o mesmo canvas 952x935 do vidro
## original, cada fragmento se encaixa 1:1 no lugar que ocupava no bloco.
const SHARD_BASE_SCALE := 0.06

var is_broken: bool = false

@onready var sprite: Sprite2D = $Sprite
@onready var hit_box: Area2D = $HitBox


func _ready() -> void:
	super._ready()
	hit_box.body_entered.connect(_on_hit_box_body_entered)


func _on_hit_box_body_entered(body: Node2D) -> void:
	if is_broken or is_processing_hit:
		return
	if body is Shard:
		return
	if body is RigidBody2D:
		hit(body, body.global_position)


func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
	if is_broken or is_processing_hit:
		return
	if bullet is Shard:
		return
	if not is_instance_valid(bullet):
		return

	is_processing_hit = true
	is_broken = true

	if impact_position == Vector2.INF:
		impact_position = bullet.global_position

	var shatter_velocity := bullet.linear_velocity
	bullet.linear_velocity *= velocity_retain
	hit_box.set_deferred("monitoring", false)

	if shatter_velocity != Vector2.ZERO:
		_spawn_shards(shatter_velocity, impact_position)

	sprite.hide()
	queue_free()


func on_hit_started(_bullet: RigidBody2D) -> void:
	pass


func on_hit_completed(_bullet: RigidBody2D, _impact_position: Vector2) -> void:
	pass


func _spawn_shards(shatter_velocity: Vector2, impact_position: Vector2) -> void:
	if shard_count <= 0:
		return
	# hit() roda dentro de callback de física (body_entered do HitBox ou
	# body_entered/sweep do Bullet). Adicionar RigidBody2D (shard) com
	# CollisionShape aqui causa "Can't change this state while flushing
	# queries" (body_set_shape_disabled). Por isso capturamos um snapshot
	# e adiamos o add_child para fora do flush via call_deferred — o self
	# sofre queue_free() logo abaixo, então nada de `self` pode ser lido
	# no método adiado.
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		return
	var origin := global_position
	var origin_scale := global_scale
	var sprite_size := sprite.get_rect().size
	var scenes := shard_scenes if not shard_scenes.is_empty() else SHARD_SCENES_FALLBACK
	call_deferred(
		"_spawn_shards_deferred",
		parent, origin, origin_scale, sprite_size, scenes,
		shatter_velocity, impact_position
	)


func _spawn_shards_deferred(
	parent: Node,
	origin: Vector2,
	origin_scale: Vector2,
	sprite_size: Vector2,
	scenes: Array[PackedScene],
	shatter_velocity: Vector2,
	impact_position: Vector2
) -> void:
	if not is_instance_valid(parent):
		return
	var to_center := origin - impact_position
	var explosion_direction: Vector2
	if to_center.length() > 1.0:
		explosion_direction = to_center.normalized()
	elif shatter_velocity.length() > 1.0:
		explosion_direction = shatter_velocity.normalized()
	else:
		explosion_direction = Vector2.UP
	var bullet_speed := shatter_velocity.length()
	var spawn_extents := sprite_size * 0.5 * origin_scale * 0.5
	for i in mini(shard_count, scenes.size()):
		var scene := scenes[i]
		if scene == null:
			continue
		var spawn_offset := Vector2(
			randf_range(-spawn_extents.x, spawn_extents.x),
			randf_range(-spawn_extents.y, spawn_extents.y)
		)
		var direction := explosion_direction.rotated(
			randf_range(-shard_spread, shard_spread)
		)
		var shard_speed := bullet_speed * randf_range(0.3, 0.7)
		shard_speed = clampf(shard_speed, shard_min_speed, shard_max_speed)
		var inst := Shard.spawn(
			parent, scene,
			impact_position + spawn_offset,
			randf() * TAU,
			direction * shard_speed,
			randf_range(
				shard_min_angular_velocity,
				shard_max_angular_velocity
			)
		)
		_fit_shard_to_glass(inst, origin_scale)


## Redimensiona a instância para a escala do vidro de origem (sprite +
## colisor, com o shape duplicado por instância — o sub_resource da cena
## é compartilhado, mesmo padrão de Bullet.apply_cannon_scale).
func _fit_shard_to_glass(inst: RigidBody2D, glass_scale: Vector2) -> void:
	(inst.get_node("Sprite2D") as Sprite2D).scale = glass_scale
	var col := inst.get_node("CollisionShape2D") as CollisionShape2D
	var rect := (col.shape as RectangleShape2D).duplicate() as RectangleShape2D
	var k := glass_scale / SHARD_BASE_SCALE
	rect.size *= k
	col.position *= k
	col.shape = rect
