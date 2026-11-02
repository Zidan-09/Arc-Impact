extends SceneTree
## Regressão do bug: disparos irregulares do canhão. A bala nascia
## DENTRO do barril — o Muzzle ficava em x=267 local, a 44.4 da parede
## superior com raio 57.717 (BarrelPivot/walls) — e o motor resolvia a
## sobreposição contra as paredes do próprio canhão nos primeiros frames:
## perda de força (62%~93% da velocidade esperada, até ~38% a -20°) e
## desvio de trajetória (até ~22°; ~2.85° = inclinação exata da parede
## superior nos demais ângulos). O efeito variava com o ângulo porque a
## gravidade muda a orientação relativa do barril.
##
## Correção: o Muzzle (spawn da bala, origem da prévia e de
## Cannon.muzzle_state_for) saiu para a boca do cano (x=360 local), onde
## o centro da bala fica a >= raio das paredes em qualquer ângulo — a
## geometria do cano rotaciona junto, então a folga é angulo-invariante.
##
## Critérios, em todos os ângulos permitidos (-20..83, incluindo os
## extremos e o horizontal) e também com força parcial:
##  1. spawn livre: o centro da bala nasce a >= raio das paredes;
##  2. nenhum contato com BarrelPivot/walls nos primeiros frames;
##  3. velocidade/direção após os passos iniciais batem com o modelo
##     analítico (v0 + gravidade por passo), sem perda nem desvio;
##  4. controle: a bala ainda colide com um obstáculo do cenário
##     (não atravessa).
##
## As colisões com obstáculos/ricochetes em si estão cobertas por
## seam_collision_test e stone_impact_test (inalterados por este fix).
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/cannon/tests/cannon_shot_test.gd

const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const CANNON_SCALE := 0.16          # Cannon.CANNON_SCALE / GridState.RESOLUTION
const SHOT_SPEED := 2000.0          # screens/game.tscn base_shot_speed
const BULLET_RADIUS := 57.717 * CANNON_SCALE
const GRAVITY := 980.0              # physics/2d/default_gravity
const DT := 1.0 / 60.0

# Extremos do @export_range do Cannon + horizontal + intermediários,
# incluindo os ângulos onde o bug era mais perceptível (-20 e -10..45).
const ANGLES: Array[float] = [-20.0, -10.0, 0.0, 10.0, 30.0, 45.0, 60.0, 83.0]
const PARTIAL_POWER := 0.35         # menor força amostrada pelo validador
const TOTAL_FRAMES := 10
# Passos em que v/direção são conferidos contra o modelo analítico
# (gravidade incluída). A tolerância absorve o linear_damp (~0.17%/passo)
# e fica MUITO abaixo da corrupção do bug (>= 1.6% de perda, >= 2.85°).
const CHECK_FRAMES: Array[int] = [0, 2]
const SPEED_TOLERANCE := 0.985
const DEV_TOLERANCE_DEG := 0.75

# Controle de colisão legítima: obstáculo à frente em 0°.
const OBSTACLE_DISTANCE := 250.0
const OBSTACLE_FRAMES := 12

var _failures := 0
var _contacts: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# Root ainda não está ready durante _initialize: o _ready dos filhos
	# é adiado e as @onready vars do canhão ficam nil até lá.
	await physics_frame
	for angle in ANGLES:
		await _case_shot(angle, 1.0)
	await _case_shot(0.0, PARTIAL_POWER)
	await _case_obstacle_control()
	if _failures == 0:
		print("CANNON_SHOT_TEST: PASS")
	else:
		printerr("CANNON_SHOT_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


## Tiro padrão: spawn livre das paredes + nenhum contato + velocidade e
## direção após os primeiros passos iguais às esperadas (só gravidade).
func _case_shot(angle: float, power: float) -> void:
	var msg := "tiro %s°, força %s" % [str(angle), str(power)]
	await _teardown()
	var cannon := await _make_cannon(angle)
	var container := Node2D.new()
	root.add_child(container)
	cannon.bullet_container = container

	var muzzle_state := cannon.get_muzzle_state()
	var origin: Vector2 = muzzle_state["origin"]
	var direction: Vector2 = muzzle_state["direction"]
	var expected_v := direction * SHOT_SPEED * clampf(power, 0.0, 1.0)

	# 1. Geometria de spawn: centro da bala a >= raio de cada parede.
	for seg in _wall_segments(cannon):
		var d := _point_seg_dist(origin, seg[0], seg[1])
		_check(d >= BULLET_RADIUS - 0.001,
			"%s => spawn livre da parede (folga %.2f px, raio %.2f)" % [
				msg, d - BULLET_RADIUS, BULLET_RADIUS])

	cannon.shoot(power)
	var bullet := container.get_child(0) as Bullet
	_contacts.clear()
	bullet.body_entered.connect(_on_bullet_contact)

	# 2/3. Contato e velocidade/direção frame a frame.
	for i in TOTAL_FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			_check(false, "%s => bala liberada antes de %d frames" % [msg, TOTAL_FRAMES])
			break
		if not (i in CHECK_FRAMES):
			continue
		# Modelo analítico: n = i+1 passos de física já aplicados.
		var n := float(i + 1)
		var model_v := expected_v + Vector2(0.0, GRAVITY) * DT * n
		var v := bullet.linear_velocity
		_check(v.length() >= model_v.length() * SPEED_TOLERANCE,
			"%s => frame %d: |v|=%.1f (esperado >= %.1f)" % [
				msg, i, v.length(), model_v.length() * SPEED_TOLERANCE])
		var dev := rad_to_deg(v.angle_to(model_v.normalized()))
		_check(absf(dev) <= DEV_TOLERANCE_DEG,
			"%s => frame %d: desvio %.3f° (<= %.2f°)" % [
				msg, i, dev, DEV_TOLERANCE_DEG])

	# 2. O canhão não pode ser colidido em nenhum frame.
	_check(_contacts.is_empty(),
		"%s => sem contato com o canhão (contatos: %s)" % [msg, str(_contacts)])


## Controle: a bala tem de colidir com um obstáculo do cenário (não
## pode atravessar) — garante que a correção não desligou colisões.
func _case_obstacle_control() -> void:
	var msg := "controle: obstáculo a %.0f px em 0°" % OBSTACLE_DISTANCE
	await _teardown()
	var cannon := await _make_cannon(0.0)
	var container := Node2D.new()
	root.add_child(container)
	cannon.bullet_container = container

	var origin: Vector2 = cannon.get_muzzle_state()["origin"]
	var wall := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20.0, 400.0)
	col.shape = rect
	wall.add_child(col)
	wall.position = origin + Vector2(OBSTACLE_DISTANCE, 0.0)
	root.add_child(wall)

	cannon.shoot(1.0)
	var bullet := container.get_child(0) as Bullet
	for i in OBSTACLE_FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			break
	_check(is_instance_valid(bullet), "%s => bala não foi liberada" % msg)
	if is_instance_valid(bullet):
		var pos := bullet.global_position
		_check(pos.x <= wall.position.x + 1.0,
			"%s => não atravessou (x=%.1f, parede em %.1f)" % [
				msg, pos.x, wall.position.x])
		_check(pos.x >= wall.position.x - 80.0,
			"%s => alcançou o obstáculo (x=%.1f)" % [msg, pos.x])


func _make_cannon(angle: float) -> Cannon:
	var cannon := CANNON_SCENE.instantiate() as Cannon
	root.add_child(cannon)
	# Espera o _ready do canhão (adiado enquanto o root inicializa).
	await physics_frame
	cannon.scale = Vector2(CANNON_SCALE, CANNON_SCALE)
	cannon.position = Vector2(400.0, 400.0)
	cannon.base_shot_speed = SHOT_SPEED
	cannon.current_angle = angle
	cannon.update_cannon_rotation()
	return cannon


## Segmentos das paredes do cano em coordenadas de mundo.
func _wall_segments(cannon: Cannon) -> Array:
	var result: Array = []
	var walls := cannon.get_node("BarrelPivot/walls") as StaticBody2D
	if walls == null:
		return result
	for child in walls.get_children():
		if not (child is CollisionShape2D):
			continue
		var col := child as CollisionShape2D
		if not (col.shape is SegmentShape2D):
			continue
		var seg := col.shape as SegmentShape2D
		result.append([
			col.global_transform * seg.a,
			col.global_transform * seg.b,
		])
	return result


func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _on_bullet_contact(body: Node) -> void:
	_contacts.append(body.name)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)


func _teardown() -> void:
	for node in root.get_children():
		if node is Cannon or node is Node2D:
			node.queue_free()
	await physics_frame
