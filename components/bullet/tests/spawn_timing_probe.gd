extends SceneTree
## Probe: QUANDO o transform chega ao servidor e ONDE o motor acha o
## contato fantasma. Espião lê body_get_state a cada _physics_process
## (antes do passo) e o handler de body_entered lê o contato direto
## (ponto/normal/collider reportados pelo motor).
##
##   godot --headless --path . -s res://components/bullet/tests/spawn_timing_probe.gd

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const CANNON_SCALE := 0.16

var bullet_rid := RID()
var spy_frames: Array = []
var spy_server: Array = []
var spy_node: Array = []


class Spy:
	extends Node
	var probe: SceneTree
	var bullet: Bullet

	func _physics_process(_delta: float) -> void:
		if bullet == null or not is_instance_valid(bullet):
			return
		var xf: Transform2D = PhysicsServer2D.body_get_state(
			bullet.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
		probe.call("_record", Engine.get_physics_frames(), xf.origin,
			bullet.global_position)


func _record(frame: int, server: Vector2, node: Vector2) -> void:
	spy_frames.append(frame)
	spy_server.append(server)
	spy_node.append(node)


func _initialize() -> void:
	_run()


func _run() -> void:
	await physics_frame
	var cannon := CANNON_SCENE.instantiate() as Cannon
	root.add_child(cannon)
	await physics_frame
	cannon.scale = Vector2(CANNON_SCALE, CANNON_SCALE)
	cannon.position = Vector2(400.0, 400.0)
	cannon.current_angle = 0.0
	cannon.update_cannon_rotation()
	var container := Node2D.new()
	root.add_child(container)
	cannon.bullet_container = container

	var spy := Spy.new()
	spy.probe = self
	root.add_child(spy)

	print("shoot no frame=", Engine.get_physics_frames())
	cannon.shoot(1.0)
	var bullet := container.get_child(0) as Bullet
	spy.bullet = bullet

	bullet.body_entered.connect(func(body: Node) -> void:
		print(">> BODY_ENTERED %s @ node=%s frame=%d" % [
			body.name, str(bullet.global_position), Engine.get_physics_frames()])
		var state := PhysicsServer2D.body_get_direct_state(bullet.get_rid())
		if state != null:
			print("   contatos=%d" % state.get_contact_count())
			for i in state.get_contact_count():
				print("   contato[%d]: local=%s collider=%s collider_pos=%s normal=%s depth=%.4f" % [
					i, str(state.get_contact_local_position(i)),
					str(state.get_contact_collider(i)),
					str(state.get_contact_collider_position(i)),
					str(state.get_contact_local_normal(i)),
					state.get_contact_impulse(i).length()])
		else:
			print("   direct_state=null (space locked?)"))

	for i in 5:
		await physics_frame
		if not is_instance_valid(bullet):
			break

	print("\nframe | server | node")
	for i in spy_frames.size():
		print("%d | %s | %s" % [spy_frames[i], str(spy_server[i]), str(spy_node[i])])

	if is_instance_valid(bullet):
		bullet.get_parent().remove_child(bullet)
		bullet.queue_free()
	cannon.queue_free()
	container.queue_free()
	quit(0)
