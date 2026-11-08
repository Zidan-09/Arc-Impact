extends SceneTree
## Probe: POR QUE a bala contata as paredes do cano logo após o spawn.
## Mede, para vários ângulos: (a) sobreposição real do círculo da bala no
## pose do muzzle contra cada shape de `walls`, (b) pose/velocidade por
## frame nos primeiros passos, (c) em que frame/pose o body_entered dispara.
##
## Roda headless:
##   godot --headless --path . -s res://components/bullet/tests/spawn_overlap_probe.gd

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const CANNON_SCALE := 0.16
const ANGLES: Array[float] = [0.0, 45.0, 83.0]


func _initialize() -> void:
	_run()


func _run() -> void:
	await physics_frame
	for angle in ANGLES:
		await _probe(angle)
	print("probe done")
	quit(0)


func _probe(angle: float) -> void:
	var cannon := CANNON_SCENE.instantiate() as Cannon
	root.add_child(cannon)
	await physics_frame
	cannon.scale = Vector2(CANNON_SCALE, CANNON_SCALE)
	cannon.position = Vector2(400.0, 400.0)
	cannon.current_angle = angle
	cannon.update_cannon_rotation()
	var container := Node2D.new()
	root.add_child(container)
	cannon.bullet_container = container

	print("\n=== angle %s ===" % str(angle))

	var walls := cannon.get_node("BarrelPivot/walls") as StaticBody2D
	# Distância do centro do muzzle a cada shape das paredes (world).
	var muzzle: Vector2 = cannon.get_muzzle_state()["origin"]
	var radius := 57.717 * CANNON_SCALE
	for owner_id in walls.get_shape_owners():
		var shape := walls.shape_owner_get_shape(owner_id, 0)
		var xf := walls.global_transform * walls.shape_owner_get_transform(owner_id)
		if shape is SegmentShape2D:
			var seg := shape as SegmentShape2D
			var a := xf * seg.a
			var b := xf * seg.b
			var dist: float = _point_seg(muzzle, a, b)
			print("  shape seg a=%s b=%s dist_centro=%.3f raio=%.3f folga=%.3f" % [
				str(a), str(b), dist, radius, dist - radius])

	# Sobreposição real no pose do muzzle (o que o motor veria no1º passo).
	var space := cannon.get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	q.shape = circle
	q.transform = Transform2D(0.0, muzzle)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = ([] as Array[RID])
	var overlaps := space.intersect_shape(q, 8)
	print("  overlap_no_muzzle: %d -> %s" % [overlaps.size(), str(
		overlaps.map(func(h): return (h.get("collider") as Node).name))])

	cannon.shoot(1.0)
	var bullet := container.get_child(0) as Bullet
	print("  spawn: pos=%s radius=%.3f phys_frame=%d" % [
		str(bullet.global_position), _bullet_radius(bullet),
		Engine.get_physics_frames()])
	bullet.body_entered.connect(func(body: Node) -> void:
		print("  >> BODY_ENTERED %s em pos=%s phys_frame=%d" % [
			body.name, str(bullet.global_position), Engine.get_physics_frames()]))

	for i in 4:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		print("  frame %d: pos=%s v=%s" % [
			str(i), str(bullet.global_position), str(bullet.linear_velocity)])

	if is_instance_valid(bullet):
		bullet.get_parent().remove_child(bullet)
		bullet.queue_free()
	cannon.queue_free()
	container.queue_free()
	await physics_frame


func _bullet_radius(bullet: Bullet) -> float:
	var col := bullet.get_node("CollisionShape2D") as CollisionShape2D
	return (col.shape as CircleShape2D).radius


func _point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
