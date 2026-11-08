extends SceneTree
## Probe de diagnóstico: o que acontece com a bala nos primeiros frames
## após Cannon.shoot() em vários ângulos. Mede velocidade/direção reais
## contra o caso de controle (paredes do cano REMOVIDAS — mesma pose).
## Também loga os contatos (body_entered) nos primeiros frames.
##
## Roda headless:
##   godot --headless --path . -s res://components/bullet/tests/cannon_spawn_probe.gd

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const CANNON_SCALE := 0.16
const ANGLES: Array[float] = [-20.0, -10.0, 0.0, 30.0, 45.0, 60.0, 83.0]


func _initialize() -> void:
	_run()


func _run() -> void:
	# Root ainda não está ready durante _initialize (o _ready dos filhos
	# é adiado e as @onready vars ficam nil até lá) — espera um frame.
	await physics_frame
	for angle in ANGLES:
		await _probe_angle(angle, true)
	for angle in ANGLES:
		await _probe_angle(angle, false)
	print("probe done")
	quit(0)


func _probe_angle(angle: float, keep_walls: bool) -> void:
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

	var walls := cannon.get_node_or_null("BarrelPivot/walls") as StaticBody2D
	if walls != null:
		walls.queue_free()
		await physics_frame

	var muzzle_state := cannon.get_muzzle_state()
	var origin: Vector2 = muzzle_state["origin"]
	var direction: Vector2 = muzzle_state["direction"]
	var base_speed: float = cannon.base_shot_speed
	var expected_v := direction * base_speed

	cannon.shoot(1.0)
	var bullet := container.get_child(0) as Bullet
	var contacts: Array[String] = []
	bullet.body_entered.connect(func(body: Node) -> void:
		contacts.append(body.name + ("(walls)" if body.name == "walls" else "")))

	print("\n=== angle %s | walls=%s | base_speed=%s ===" % [
		str(angle), str(keep_walls), str(base_speed)])
	print("spawn origin=", origin, " dir=", direction,
		" v=", bullet.linear_velocity)
	for i in 4:
		await physics_frame
		if not is_instance_valid(bullet):
			print("  frame %d: bullet freed" % i)
			break
		var v: Vector2 = bullet.linear_velocity
		var dev := rad_to_deg(v.angle_to(expected_v))
		var speed_pct := v.length() / base_speed * 100.0
		print("  frame %d: |v|=%.1f (%.1f%% do esperado) dev=%.3f deg | v=%s | contatos=%s" % [
			i, v.length(), speed_pct, dev, str(v), str(contacts)])

	if is_instance_valid(bullet):
		bullet.get_parent().remove_child(bullet)
		bullet.queue_free()
	cannon.queue_free()
	container.queue_free()
	await physics_frame
