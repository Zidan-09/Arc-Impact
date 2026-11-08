extends SceneTree
## Probe: o que o SERVIDOR de física vê na bala recém-instanciada —
## transform server-side vs nó, raio do shape, e contato via CCD.
## Variantes (ângulo 0):
##   A) baseline
##   B) raio forçado a 1px após shoot (o motor usa este shape?)
##   C) bala teleportada perto do canhão MAS longe das paredes (+300px)
##   D) CCD off (controle)
##
##   godot --headless --path . -s res://components/bullet/tests/spawn_server_probe.gd

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const CANNON_SCALE := 0.16
const ANGLE := 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	await physics_frame
	await _variant("A baseline", "none")
	await _variant("B raio 1px", "tiny_radius")
	await _variant("C +300px longe", "far")
	await _variant("D ccd off", "ccd_off")
	print("probe done")
	quit(0)


func _variant(title: String, mode: String) -> void:
	var cannon := CANNON_SCENE.instantiate() as Cannon
	root.add_child(cannon)
	await physics_frame
	cannon.scale = Vector2(CANNON_SCALE, CANNON_SCALE)
	cannon.position = Vector2(400.0, 400.0)
	cannon.current_angle = ANGLE
	cannon.update_cannon_rotation()
	var container := Node2D.new()
	root.add_child(container)
	cannon.bullet_container = container

	print("\n=== %s ===" % title)
	cannon.shoot(1.0)
	var bullet := container.get_child(0) as Bullet
	var col := bullet.get_node("CollisionShape2D") as CollisionShape2D
	var dir: Vector2 = cannon.get_muzzle_state()["direction"]
	match mode:
		"tiny_radius":
			var c := (col.shape as CircleShape2D).duplicate() as CircleShape2D
			c.radius = 1.0
			col.shape = c
		"far":
			bullet.global_position += dir * 300.0
		"ccd_off":
			bullet.continuous_cd = RigidBody2D.CCD_MODE_DISABLED

	var server_xf: Transform2D = PhysicsServer2D.body_get_state(
		bullet.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	print("  pos no: %s | pos server: %s | raio: %.3f | ccd=%d" % [
		str(bullet.global_position), str(server_xf.origin),
		(col.shape as CircleShape2D).radius, bullet.continuous_cd])

	var fired := [false]
	bullet.body_entered.connect(func(body: Node) -> void:
		fired[0] = true
		print("  >> BODY_ENTERED %s @ pos_no=%s pos_server=%s" % [
			body.name, str(bullet.global_position),
			str(PhysicsServer2D.body_get_state(bullet.get_rid(),
				PhysicsServer2D.BODY_STATE_TRANSFORM).origin)]))

	for i in 3:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		var xf: Transform2D = PhysicsServer2D.body_get_state(
			bullet.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
		print("  frame %d: no=%s server=%s v=%s contato=%s" % [
			i, str(bullet.global_position), str(xf.origin),
			str(bullet.linear_velocity), str(fired[0])])

	if is_instance_valid(bullet):
		bullet.get_parent().remove_child(bullet)
		bullet.queue_free()
	cannon.queue_free()
	container.queue_free()
	await physics_frame
