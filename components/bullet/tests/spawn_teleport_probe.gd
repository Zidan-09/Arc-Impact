extends SceneTree
## Probe: o CCD do motor varre o TELEPORTE de spawn (origem do container
## -> muzzle) como se fosse movimento, tocando as paredes do cano.
## Variantes (ângulo 0, CCD ligado salvo indicação):
##   P1) container em (0,0), posição setada APÓS add_child (baseline)
##   P2) container em (2000,2000), posição setada APÓS add_child
##       (caminho fantasma (2000,2000)->muzzle NÃO passa perto do cano)
##   P3) container em (0,0), posição setada ANTES de add_child
##       (sem teleport: corpo nasce no muzzle)
##
##   godot --headless --path . -s res://components/bullet/tests/spawn_teleport_probe.gd

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const CANNON_SCALE := 0.16
const ANGLE := 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	await physics_frame
	await _variant("P1 container (0,0) pos depois", Vector2.ZERO, false)
	await _variant("P2 container (2000,2000) pos depois", Vector2(2000, 2000), false)
	await _variant("P3 container (0,0) pos ANTES do add_child", Vector2.ZERO, true)
	print("probe done")
	quit(0)


func _variant(title: String, container_pos: Vector2, pos_before_add: bool) -> void:
	var cannon := CANNON_SCENE.instantiate() as Cannon
	root.add_child(cannon)
	await physics_frame
	cannon.scale = Vector2(CANNON_SCALE, CANNON_SCALE)
	cannon.position = Vector2(400.0, 400.0)
	cannon.current_angle = ANGLE
	cannon.update_cannon_rotation()
	var container := Node2D.new()
	container.position = container_pos
	root.add_child(container)
	cannon.bullet_container = container

	print("\n=== %s ===" % title)
	if is_instance_valid(cannon.recoil_tween) and cannon.recoil_tween.is_valid():
		cannon.recoil_tween.kill()
	if pos_before_add:
		# Espelha um shoot() que posiciona ANTES de add_child.
		var bullet := BULLET_SCENE.instantiate() as Bullet
		bullet.apply_cannon_scale(cannon.global_scale)
		var muzzle: Vector2 = cannon.get_muzzle_state()["origin"]
		bullet.position = container.to_local(muzzle)
		container.add_child(bullet)
		bullet.add_to_group("bullets")
		bullet.linear_velocity = (cannon.get_muzzle_state()["direction"] as Vector2) \
			* cannon.base_shot_speed
	else:
		cannon.shoot(1.0)
	var bullet := container.get_child(0) as Bullet
	var server_xf: Transform2D = PhysicsServer2D.body_get_state(
		bullet.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	print("  no=%s server=%s" % [str(bullet.global_position), str(server_xf.origin)])

	var fired := [false]
	bullet.body_entered.connect(func(body: Node) -> void:
		fired[0] = true
		print("  >> BODY_ENTERED %s @ no=%s" % [
			body.name, str(bullet.global_position)]))

	for i in 3:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		print("  frame %d: no=%s v=%s contato=%s" % [
			i, str(bullet.global_position), str(bullet.linear_velocity),
			str(fired[0])])

	if is_instance_valid(bullet):
		bullet.get_parent().remove_child(bullet)
		bullet.queue_free()
	cannon.queue_free()
	container.queue_free()
	await physics_frame
