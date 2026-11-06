extends SceneTree
## Regressão do bug: bala NÃO ricocheeteia no Floor (morria estática no
## primeiro contato). Causa: floor.tscn sem physics_material_override =>
## combinação de material no CCD (Bullet._apply_solid_bounce) dava
## e = max(0,0) = 0 e f = sqrt(1*1) = 1 => vt*(1-f) + normal*(-e*vn) =
## Vector2.ZERO, destruindo toda a velocidade. Correção: floor.tscn com
## PhysicsMaterial(bounce 0.7, atrito 0), no mesmo padrão de metal/pedra.
##
## Usa a geometria real do jogo: fileira de floor.tscn (escala 0.2 =>
## tiles de 100px, colisor 1.01) e a bala real (bullet.tscn, escala de
## canhão 0.16 => raio ~9.23px), mirando o centro da fileira.
##
## Cenários: ângulos 10° (rasante), 45° e 80° (quase perpendicular)
## × velocidades 150 / 400 / 2000 / 6000 px/s, mais uma queda quase
## vertical exigindo 3 ricochetes consecutivos com decaimento.
##
## Critérios por cenário:
##  1. nunca entra no colisor do floor sobre a fileira (sem tunelar);
##  2. ricochete ocorre: a velocidade vertical vira para cima após o
##     contato, com folga (|v.y| de subida > 20 px/s);
##  3. a velocidade NÃO morre no contato (o bug original zerava |v|;
##     no contato a bala tem de seguir com |v| > 50 px/s).
##
## Detecção de contato: banda `pos.y + raio >= -1` OU assinatura de
## ricochete (v.y passa de descendo para subindo) — em alta velocidade o
## CCD prende e ejeta no MESMO tick, e a banda nunca é observada.
## Saída da fileira (|x| > metade da fileira) após o ricochete encerra o
## cenário: a bala voou para fora dos tiles e cai no vazio, o que é
## comportamento correto, não tunelamento.
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/bullet/tests/floor_ricochet_test.gd

const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const FLOOR_SCENE: PackedScene = preload("res://components/floor/floor.tscn")

const CANNON_SCALE := 0.16
const TILE := 100.0                 # 500 * escala 0.2
const TILE_COLL := TILE * 1.01      # colisor com a sobreposição 1.01 do floor.tscn
const TILES := 9
const ROW_HALF := TILES * TILE * 0.5 + TILE_COLL * 0.5
const MAX_FRAMES := 300
const MIN_BOUNCE_UP := 20.0         # folga do ricochete (e=0.7: 70% do impacto)
const MIN_CONTACT_SPEED := 50.0     # o bug original zerava a velocidade

var _failures := 0
var _world: Node2D


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	for angle in [10.0, 45.0, 80.0]:
		for speed in [150.0, 400.0, 2000.0, 6000.0]:
			await _case(angle, speed)
	# Ricochetes consecutivos: queda quase vertical, a bala fica sobre a
	# fileira e tem de saltar 3x com decaimento (e=0.7) a cada impacto.
	await _case(80.0, 150.0, 3)
	if _failures == 0:
		print("FLOOR_RICOCHET_TEST: PASS")
	else:
		printerr("FLOOR_RICOCHET_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


func _case(angle_deg: float, speed: float, need_flips: int = 1) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	for i in TILES:
		var tile := FLOOR_SCENE.instantiate() as Node2D
		tile.scale = Vector2(0.2, 0.2)
		tile.position = Vector2(
			(float(i) - (TILES - 1) * 0.5) * TILE, TILE_COLL * 0.5)
		_world.add_child(tile)

	# Trajetória que passa pelo ponto-alvo (0, -2): rente ao colisor.
	var rad := deg_to_rad(angle_deg)
	var dir := Vector2(cos(rad), sin(rad))   # y positivo = p/ baixo
	var spawn := Vector2(0.0, -2.0) - dir * 400.0

	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = spawn
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = dir * speed
	_world.add_child.call_deferred(bullet)
	await physics_frame

	var radius := 57.717 * CANNON_SCALE
	var tag := "%3.0f° @ %5.0f px/s" % [angle_deg, speed]

	var contact := false
	var contact_speed := 0.0
	var bounced := false
	var max_up := 0.0
	var flips := 0
	var up_history: Array[float] = []
	var tunneled := false
	var left_row := false
	var prev_vy := 0.0

	for f in MAX_FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		var pos := bullet.global_position
		var v := bullet.linear_velocity
		var over_row := absf(pos.x) <= ROW_HALF
		# Contato: banda de toque OU o ricochete que o CCD aplicou no
		# mesmo tick do impacto (alta velocidade: ejeção imediata).
		var bounce_flip := prev_vy > 1.0 and v.y < -1.0
		if not contact and (pos.y + radius >= -1.0 or bounce_flip):
			contact = true
			contact_speed = v.length()
		if bounce_flip:
			bounced = true
			flips += 1
			max_up = maxf(max_up, -v.y)
			up_history.append(-v.y)
		prev_vy = v.y
		if contact and over_row and pos.y > radius * 0.5:
			tunneled = true
			break
		if bounced and not over_row:
			left_row = true
			break
		if flips >= need_flips and max_up > MIN_BOUNCE_UP \
				and pos.y + radius < -31.0:
			break

	_check(contact, "%s => contato com o floor registrado" % tag)
	_check(not tunneled, "%s => nunca entrou no colisor sobre a fileira" % tag)
	_check(bounced and max_up > MIN_BOUNCE_UP,
		"%s => ricochete: subida máxima %.0f px/s (esperado > %.0f)" % [
			tag, max_up, MIN_BOUNCE_UP])
	_check(contact and contact_speed > MIN_CONTACT_SPEED,
		"%s => velocidade preservada no contato: %.0f px/s (bug original zerava)" % [
			tag, contact_speed])
	if need_flips > 1:
		_check(flips >= need_flips,
			"%s => %d ricochetes consecutivos (obtidos: %d)" % [
				tag, need_flips, flips])
		if up_history.size() >= 2:
			_check(up_history[1] < up_history[0],
				"%s => decaimento a cada impacto: %.0f -> %.0f (e=0.7)" % [
					tag, up_history[0], up_history[1]])
	if left_row:
		print("  [info] %s: saiu da fileira após o ricochete (comportamento correto)" % tag)
	_teardown()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)


func _teardown() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		_world = null
	await physics_frame
