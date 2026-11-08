extends SceneTree
## Probe: isolar a CAUSA do body_entered com `walls` logo após o spawn.
## Variantes (mesma pose/ângulo 0):
##   A) baseline
##   B) velocidade zerada (só sobreposição importa)
##   C) spawn +10px de folga extra
##   D) continuous_cd desligado (CCD do motor)
##   E) recoil do barril morto (barrel parado)
## Cada variante loga posição da bala e do BarrelPivot por frame e o
## instante do body_entered.
##
##   godot --headless --path . -s res://components/bullet/tests/spawn_contact_probe.gd

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const CANNON_SCALE := 0.16
const ANGLE := 0.0
const FRAMES := 6


func _initialize() -> void:
	_run()


func _run() -> void:
	await physics_frame
	await _variant("A baseline", "none")
	await _variant("B v=0", "zero_v")
	await _variant("C +10px folga", "extra_gap")
	await _variant("D ccd off", "ccd_off")
	await _variant("E recoil morto", "no_recoil")
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
	var pivot := cannon.get_node("BarrelPivot") as Node2D
	var dir: Vector2 = (cannon.get_muzzle_state()["direction"] as Vector2)
	match mode:
		"zero_v":
			bullet.linear_velocity = Vector2.ZERO
		"extra_gap":
			bullet.global_position += dir * 10.0
		"ccd_off":
			bullet.continuous_cd = RigidBody2D.CCD_MODE_DISABLED
		"no_recoil":
			if cannon.recoil_tween != null and cannon.recoil_tween.is_valid():
				cannon.recoil_tween.kill()
				pivot.position = cannon.barrel_initial_position

	var fired := [false]
	bullet.body_entered.connect(func(body: Node) -> void:
		fired[0] = true
		print("  >> BODY_ENTERED %s @ frame=%d pos=%s" % [
			body.name, Engine.get_physics_frames(), str(bullet.global_position)]))

	print("  spawn pos=%s v=%s frame=%d" % [
		str(bullet.global_position), str(bullet.linear_velocity),
		Engine.get_physics_frames()])
	for i in FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			print("  frame %d: bullet freed" % i)
			break
		print("  frame %d: bullet=%s v=%s pivot=%s contato=%s" % [
			i, str(bullet.global_position), str(bullet.linear_velocity),
			str(pivot.global_position), str(fired[0])])

	if is_instance_valid(bullet):
		bullet.get_parent().remove_child(bullet)
		bullet.queue_free()
	cannon.queue_free()
	container.queue_free()
	await physics_frame
