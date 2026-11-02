extends SceneTree
## Probe temporário: isolar a origem do contato fantasma com as paredes
## do canhão. Cenários:
##   A) shoot() normal (baseline)
##   B) shoot() + mata o tween de recoil imediatamente
##   C) shoot() + continuous_cd desativado
##   D) bala criada à mão no muzzle (sem shoot/recoil)
##   E) bala criada à mão 60px ACIMA do muzzle (livre)
##   F) shoot() + re-registra a shape (bcol.shape = bcol.shape)
##   G) bala criada 1 frame DEPOIS (spawn separado da criação)

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const SCALE := 0.16


func _initialize() -> void:
	_run()


func _run() -> void:
	await _scenario("A baseline", func(c, b): pass)
	await _scenario("B sem recoil", func(c, b): (c.recoil_tween as Tween).kill())
	await _scenario("C sem engine CCD", func(c, b): b.continuous_cd = 0)
	await _scenario("D spawn mao (sem shoot)", func(c, b): pass, true)
	await _scenario("E livre -60y", func(c, b): pass, true, Vector2(0.0, -60.0))
	await _scenario("F re-registra shape", func(c, b):
		var col := b.get_node("CollisionShape2D") as CollisionShape2D
		col.shape = col.shape)
	await _scenario("G spawn 1 frame depois", func(c, b): pass, false, Vector2.ZERO, true)
	quit(0)


func _scenario(tag: String, tweak: Callable, manual := false,
		offset := Vector2.ZERO, delayed := false) -> void:
	var cannon := CANNON_SCENE.instantiate() as Cannon
	root.add_child(cannon)
	await physics_frame
	cannon.scale = Vector2(SCALE, SCALE)
	cannon.position = Vector2(400.0, 400.0)
	cannon.base_shot_speed = 2000.0
	cannon.current_angle = 0.0
	cannon.update_cannon_rotation()
	var container := Node2D.new()
	root.add_child(container)
	cannon.bullet_container = container

	var bullet: Bullet
	if manual:
		bullet = _spawn_manual(cannon, container, offset)
	else:
		cannon.shoot(1.0)
		bullet = container.get_child(0) as Bullet
		if delayed:
			# Recria a bala em um frame separado da criação do corpo.
			bullet.queue_free()
			await physics_frame
			bullet = _spawn_manual(cannon, container, offset)
		else:
			tweak.call(cannon, bullet)
	if manual:
		tweak.call(cannon, bullet)

	var spawn: Vector2 = bullet.global_position
	var pushed: Vector2 = spawn
	var contacted := false
	bullet.body_entered.connect(func(_body): contacted = true)
	for i in 2:
		await physics_frame
		if is_instance_valid(bullet):
			pushed = bullet.global_position
	await physics_frame
	var delta := pushed - spawn
	print("%-28s contato=%-5s spawn->pos=(%.2f, %.2f) |d|=%.2f" % [
		tag, str(contacted), delta.x, delta.y, delta.length()])
	if is_instance_valid(bullet):
		bullet.queue_free()
	cannon.queue_free()
	container.queue_free()
	await physics_frame


func _spawn_manual(cannon: Cannon, container: Node2D, offset: Vector2) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	container.add_child(bullet)
	bullet.add_to_group("bullets")
	bullet.apply_cannon_scale(cannon.global_scale)
	var state := cannon.get_muzzle_state()
	bullet.global_position = state["origin"] + offset
	bullet.linear_velocity = state["direction"] * cannon.base_shot_speed
	return bullet
