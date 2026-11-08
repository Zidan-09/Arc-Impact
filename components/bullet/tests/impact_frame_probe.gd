extends SceneTree
## Sonda: `Engine.get_physics_frames()` é o MESMO valor num tick de
## física inteiro — callback de nó (`_physics_process`, onde rodam o
## raio e o CCD da bala) E a emissão de sinais de contato
## (`body_entered`, disparado no passo de física)? É a base da regra
## "1 onomatopeia por disparo por frame" (dedup por frame na bala):
## se os dois caminhos do MESMO tick vissem frames diferentes, um
## impacto poderia gerar dois textos.
## Uso: godot --headless --path . -s res://components/bullet/tests/impact_frame_probe.gd


class Spy:
	extends Node
	var last_frame: int = -1

	func _physics_process(_delta: float) -> void:
		last_frame = Engine.get_physics_frames()


var _spy := Spy.new()
var _world := Node2D.new()
var _area: Area2D
var _signal_seen := false


func _initialize() -> void:
	root.add_child(_world)
	_world.add_child(_spy)

	# Chão: para a bala depois da área (a área relata primeiro).
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(400.0, 40.0)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	floor_body.position = Vector2(0.0, 300.0)
	_world.add_child(floor_body)

	# Área de detecção no caminho da bala.
	_area = Area2D.new()
	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = Vector2(400.0, 40.0)
	area_shape.shape = area_rect
	_area.add_child(area_shape)
	_area.position = Vector2(0.0, 150.0)
	_area.body_entered.connect(_on_area_body_entered)
	_world.add_child(_area)

	# Bala caindo: passa pela área e para no chão.
	var bullet := RigidBody2D.new()
	var bullet_shape := CollisionShape2D.new()
	var bullet_circle := CircleShape2D.new()
	bullet_circle.radius = 8.0
	bullet_shape.shape = bullet_circle
	bullet.add_child(bullet_shape)
	bullet.position = Vector2(0.0, -100.0)
	bullet.linear_velocity = Vector2(0.0, 600.0)
	_world.add_child(bullet)

	await _finish()


func _on_area_body_entered(_body: Node2D) -> void:
	if _signal_seen:
		return
	_signal_seen = true
	var signal_frame := Engine.get_physics_frames()
	print("[probe] sinal body_entered: frame=%d | spy(_physics_process)=%d | mesmo=%s" % [
		signal_frame, _spy.last_frame,
		str(signal_frame == _spy.last_frame)])


func _finish() -> void:
	for i in 60:
		await physics_frame
	if not _signal_seen:
		print("[probe] sinal NÃO disparou (setup falhou)")
	quit(0)
