extends SceneTree
## Sonda de integração (feature onomatopeias): em QUE ordem os caminhos
## de impacto do vidro rodam, e se o roteador da bala (`_route_hit`)
## chega a ver o vidro antes do `body_entered` próprio do HitBox.
##
## Motivo: o texto de impacto nasce no roteador único da bala (dedup por
## instância). Se o caminho direto do vidro (`GlassObstacle.hit` via
## sinal do HitBox) vencer a corrida, o roteador nunca roda para aquele
## vidro — que é `queue_free`'d no mesmo frame — e o texto não nasceria.
## A sonda também responde se o `body_entered` da bala enxerga Area2D
## (contact_monitor), que decidiria se o roteador roda SEMPRE no mesmo
## flush, mesmo quando o caminho direto vence.
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/bullet/tests/impact_route_probe.gd

const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")

const TILE := 64.0 * 1.01
const CANNON_SCALE := 0.16
const SPAWN_HEIGHT := 120.0

var _world: Node2D


class ProbeGlass:
	extends GlassObstacle
	var hits := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hits += 1
		print("[probe] GLASS_HIT #%d (volta do roteador? v=%.0f)" % [
			hits, bullet.linear_velocity.length() if is_instance_valid(bullet) else -1.0])
		super.hit(bullet, impact_position)


func _initialize() -> void:
	_run()


func _run() -> void:
	# 1. Pergunta isolada: body_entered de RigidBody2D com contact_monitor
	#    dispara para sobreposição com Area2D?
	await _probe_area_vs_contact_monitor()
	# 2. Corrida roteador x caminho direto do vidro, em 3 velocidades.
	for speed in [2000.0, 400.0, 150.0]:
		await _probe_glass_race(speed)
	print("IMPACT_ROUTE_PROBE: fim")
	quit(0)


func _probe_area_vs_contact_monitor() -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var body := RigidBody2D.new()
	body.contact_monitor = true
	body.max_contacts_reported = 8
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	col.shape = circle
	body.add_child(col)
	var area := Area2D.new()
	var acol := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200.0, 200.0)
	acol.shape = rect
	area.add_child(acol)
	_world.add_child(area)
	_world.add_child(body)

	var area_saw := [false]
	var body_saw := [false]
	area.body_entered.connect(func(_b): area_saw[0] = true)
	body.body_entered.connect(func(_b): body_saw[0] = true)
	# Repousa o corpo DENTRO da área: se o contact_monitor enxerga
	# areas, body.body_entered dispara no primeiro flush.
	body.position = Vector2.ZERO
	area.position = Vector2.ZERO
	for i in 10:
		await physics_frame
	print("[probe] area.body_entered=%s | body.body_entered(area)=%s" % [
		str(area_saw[0]), str(body_saw[0])])
	_teardown()


func _probe_glass_race(speed: float) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var glass := ProbeGlass.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var hit_box := Area2D.new()
	hit_box.name = "HitBox"
	var hcol := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	hcol.shape = rect
	hit_box.add_child(hcol)
	glass.add_child(sprite)
	glass.add_child(hit_box)
	glass.position = Vector2.ZERO
	_world.add_child(glass)

	print("[probe] --- vidro a %.0f px/s ---" % speed)
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT)
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = Vector2(0.0, speed)
	_world.add_child.call_deferred(bullet)
	await physics_frame

	for i in 90:
		await physics_frame
		if not is_instance_valid(bullet):
			break
	var hits := -1
	if is_instance_valid(glass):
		hits = glass.hits
	print("[probe] vidro válido=%s | hits=%d | v_final=%.0f" % [
		str(is_instance_valid(glass)), hits,
		bullet.linear_velocity.length() if is_instance_valid(bullet) else -1.0])
	_teardown()


func _teardown() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		_world = null
	await physics_frame
