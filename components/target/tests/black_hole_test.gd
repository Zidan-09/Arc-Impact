extends SceneTree
## Teste headless do alvo "buraco negro" (components/target/target.tscn).
## Valida o critério de sucesso da troca de colisão por Area2D:
##  - estrutura: raiz sem shape (logo não há superfície p/ ricochete) e
##    as Areas2D com o raio do ring/portal + mask que só enxerga balas;
##  - rotações preservadas: ring anti-horário, portal horário, base parado;
##  - dentro do campo não escapa (inclusive com a gravidade do projeto
##    empurrando CONTRA o centro), a trajetória fica curva e o disparo é
##    absorvido SÓ no portal;
##  - após a absorção a bala some da cena e `target_hit` é emitido 1x.
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/target/tests/black_hole_test.gd

const TARGET_SCENE: PackedScene = preload("res://components/target/target.tscn")
const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")

# Extensões visíveis medidas nas texturas (1024x1024, centradas em 512).
const RING_R := 305.0
const PORTAL_R := 149.4
const SHOT_SPEED := 2000.0   # base_shot_speed do screens/game.tscn
const MAX_FRAMES := 900
const TOLERANCE := 1.5       # folga de amostragem p/ declarar fuga (px)

var _failures := 0
var _gravity := 980.0
var _cannon_scale := 0.16
var _bullet_r := 0.0
var _field_r := 0.0
var _absorb_r := 0.0
var _target: Target
var _hit_count := 0
var _hit_dist := -1.0
var _hit_vel := Vector2.ZERO


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await physics_frame
	await _setup()
	_case_structure()
	await _case_spin()

	# Bala caindo bem devagar: atravessa a região onde existia o corpo
	# físico antigo e chega ao portal => prova que não há mais obstáculo.
	await _case_shot("vertical lento (sem ricochete)", Vector2(0, -70), Vector2(0, 40), true)
	# Passa RASANTE por dentro do campo, fora do portal: obrigado a curvar.
	await _case_shot(
		"rasante 1000px/s (curva obrigatória)",
		Vector2(-250, -63.6), Vector2(1000, 0), true, 15.0
	)
	# Cruzamento horizontal com agravamento: só é absorvido se curvar.
	await _case_shot("cruzando 800px/s", Vector2(-200, 0), Vector2(800, 0), true)
	# Sobe contra a gravidade até a borda do campo e é puxado de volta.
	await _case_shot(
		"subindo contra a gravidade (sem fuga)",
		Vector2(0, 64), Vector2(0, -250), true
	)

	for angle_deg in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
		await _case_shot(
			"varredura %d graus" % int(angle_deg),
			-dir * 180.0, dir * SHOT_SPEED, true
		)

	if _failures == 0:
		print("BLACK_HOLE_TEST: PASS")
	else:
		printerr("BLACK_HOLE_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)


func _circle_r(node: Node) -> float:
	var col := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or not (col.shape is CircleShape2D):
		return -1.0
	return (col.shape as CircleShape2D).radius


func _setup() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	_cannon_scale = Cannon.CANNON_SCALE.x / GridState.RESOLUTION

	var probe: Bullet = BULLET_SCENE.instantiate() as Bullet
	probe.apply_cannon_scale(Vector2(_cannon_scale, _cannon_scale))
	_bullet_r = _circle_r(probe)
	probe.free()

	_target = TARGET_SCENE.instantiate() as Target
	_target.position = Vector2(640, 360)
	_target.scale = MaterialRules.target_scale()
	root.add_child(_target)
	_target.target_hit.connect(_on_target_hit)
	await physics_frame

	_field_r = _circle_r(_target.get_node_or_null("GravityArea")) * _target.scale.x + _bullet_r
	_absorb_r = _circle_r(_target.get_node_or_null("AbsorptionArea")) * _target.scale.x + _bullet_r
	print("alvo escala=%s  bala_r=%.2f  campo=%.2f  portal=%.2f  gravidade=%.0f"
		% [str(_target.scale), _bullet_r, _field_r, _absorb_r, _gravity])


func _on_target_hit(body: Bullet) -> void:
	_hit_count += 1
	if is_instance_valid(body):
		_hit_dist = _target.global_position.distance_to(body.global_position)
		_hit_vel = body.linear_velocity


func _case_structure() -> void:
	var names := PackedStringArray()
	var direct_shapes := 0
	for child in _target.get_children():
		names.append(String(child.name))
		if child is CollisionShape2D:
			direct_shapes += 1

	_check(",".join(names) == "base,portal,ring,GravityArea,AbsorptionArea",
		"estrutura = %s" % ",".join(names))
	_check(direct_shapes == 0,
		"raiz sem CollisionShape2D (sem corpo físico => impossível ricocheter)")
	_check(not _target.has_method("hit"),
		"Target sem hit() — o roteamento de colisão antigo saiu")

	var gravity_area := _target.get_node_or_null("GravityArea") as Area2D
	_check(gravity_area != null, "GravityArea existe e é Area2D")
	if gravity_area != null:
		_check(gravity_area.collision_mask == 2,
			"GravityArea mask=2 (só o bit das balas), veio %d" % gravity_area.collision_mask)
		_check(gravity_area.collision_layer == 4,
			"GravityArea layer=4 (raycast da bala não enxerga), veio %d" % gravity_area.collision_layer)
		_check(absf(_circle_r(gravity_area) - RING_R) < 1.0,
			"raio da GravityArea = borda externa do ring (%.1f)" % _circle_r(gravity_area))

	var absorb_area := _target.get_node_or_null("AbsorptionArea") as Area2D
	_check(absorb_area != null, "AbsorptionArea existe é Area2D")
	if absorb_area != null:
		_check(absorb_area.collision_mask == 2,
			"AbsorptionArea mask=2 (só o bit das balas), veio %d" % absorb_area.collision_mask)
		_check(absorb_area.collision_layer == 4,
			"AbsorptionArea layer=4 (raycast da bala não enxerga), veio %d" % absorb_area.collision_layer)
		_check(absf(_circle_r(absorb_area) - PORTAL_R) < 1.0,
			"raio da AbsorptionArea = região visual do portal (%.1f)" % _circle_r(absorb_area))
	_check(_absorb_r < _field_r,
		"portal (%.1f) fica dentro do campo (%.1f)" % [_absorb_r, _field_r])

	var probe: Bullet = BULLET_SCENE.instantiate() as Bullet
	_check(probe.collision_layer == 3,
		"bala layer 3 = mundo + 'pode ser atraído', veio %d" % probe.collision_layer)
	_check(probe.collision_mask == 1,
		"bala mask 1 inalterada (colisões existentes intactas), veio %d" % probe.collision_mask)
	probe.free()


func _case_spin() -> void:
	var ring := _target.get_node_or_null("ring") as Sprite2D
	var portal := _target.get_node_or_null("portal") as Sprite2D
	var base := _target.get_node_or_null("base") as Sprite2D
	if ring == null or portal == null or base == null:
		_check(false, "sprites base/portal/ring presentes")
		return

	var r0 := ring.rotation
	var p0 := portal.rotation
	var b0 := base.rotation
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 150:
		await process_frame

	var dr := ring.rotation - r0
	var dp := portal.rotation - p0
	var db := base.rotation - b0
	_check(dr < 0.0, "ring gira anti-horário (delta %+.5f rad)" % dr)
	_check(dp > 0.0, "portal gira horário (delta %+.5f rad)" % dp)
	_check(db == 0.0, "base continua estático (delta %+.5f rad)" % db)
	_check(absf(dr + dp) <= absf(dr) * 0.05,
		"ring/portal giram na mesma velocidade oposta (%+.5f / %+.5f)" % [dr, dp])


## Dispara uma bala a `offset` do centro do alvo com `velocity` e
## acompanha até ela ser absorvida ou estourar o orçamento de frames.
func _case_shot(
	label: String,
	offset: Vector2,
	velocity: Vector2,
	must_enter: bool,
	min_curve_deg: float = 0.0
) -> void:
	_hit_count = 0
	_hit_dist = -1.0
	_hit_vel = Vector2.ZERO

	var start := _target.global_position + offset
	var bullet: Bullet = BULLET_SCENE.instantiate() as Bullet
	bullet.position = start
	root.add_child(bullet)
	bullet.global_position = start
	bullet.apply_cannon_scale(Vector2(_cannon_scale, _cannon_scale))
	bullet.linear_velocity = velocity

	var entered := false
	var escaped := false
	var min_radial := INF
	var entry_dir := velocity.normalized()
	var frames := 0

	while frames < MAX_FRAMES:
		await physics_frame
		frames += 1
		if _hit_count > 0:
			entered = true  # ser absorvido implica ter atravessado o campo
			break
		if not is_instance_valid(bullet):
			break

		var to_center := _target.global_position - bullet.global_position
		var d := to_center.length()
		if not entered:
			if d <= _field_r:
				entered = true
				entry_dir = bullet.linear_velocity.normalized()
			elif d > _field_r + 700.0:
				break  # errou o alvo por muito longe; nada a esperar
			continue

		if d > _field_r + TOLERANCE:
			escaped = true
			break
		min_radial = minf(min_radial, bullet.linear_velocity.dot(to_center / maxf(d, 0.001)))

	var absorbed := _hit_count > 0
	var curve_deg := 0.0
	if absorbed:
		curve_deg = rad_to_deg(entry_dir.angle_to(_hit_vel.normalized()))

	await physics_frame
	await physics_frame
	var freed := not is_instance_valid(bullet)
	if is_instance_valid(bullet):
		bullet.queue_free()
	for trail in get_nodes_in_group("bullet_trails"):
		(trail as Node).queue_free()

	if must_enter:
		_check(entered, "%s: entrou no campo gravitacional" % label)
	_check(not escaped, "%s: dentro do campo não escapou (campo=%.1f)" % [label, _field_r])
	_check(absorbed, "%s: foi absorvido no portal" % label)
	_check(_hit_count == 1,
		"%s: target_hit emitido exatamente 1x (veio %d)" % [label, _hit_count])
	_check(_hit_dist >= 0.0 and _hit_dist <= _absorb_r + 1.0,
		"%s: acerto registrado no portal (dist=%.2f, limite=%.2f)" % [label, _hit_dist, _absorb_r])
	_check(freed, "%s: bala removida da cena após a absorção" % label)
	if min_curve_deg > 0.0 and entered:
		_check(curve_deg >= min_curve_deg,
			"%s: trajetória curvou %.1f° dentro do campo (mín %.0f°)"
			% [label, curve_deg, min_curve_deg])
	if min_radial != INF:
		# Um ricochete real no corpo físico antigo viraria a radial para
		# ~-1000 px/s (volta do impacto). O que vemos em tiros rasantes é
		# um artefato de amostragem quando a bala passa a ~1cm do centro
		# e o vetor `to_center` vira entre frames (~±200 px/s).
		_check(min_radial > -400.0,
			"%s: componente radial nunca virou fuga (%.0f px/s) = sem ricochete"
			% [label, min_radial])
