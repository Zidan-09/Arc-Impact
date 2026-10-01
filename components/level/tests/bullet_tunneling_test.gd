extends SceneTree
## Regressão do tunneling (docs/plan.md §5 item 7).
## N tiros a potência máxima (2000 px/s → ~33px/tick) contra o alvo fino
## e o poste de vidro 0.05 — o pior caso (corda < 33px em rasante).
## Conta atravessamentos silenciosos: tiro que cruza o corpo sem
## registrar hit (sem target_hit, sem destruição, sem ricochete).
## Pós-correção (CCD cast-shape + roteador varrido prev→current na bala)
## deve ser 0. Roda headless, sem framework:
##   godot --headless --path . -s res://components/level/tests/bullet_tunneling_test.gd
## Saída: "BULLET_TUNNELING_TEST: PASS" (exit 0) ou FAIL (exit 1).


func _initialize() -> void:
	Engine.time_scale = 1.0
	_run_all()


func _run_all() -> void:
	await physics_frame
	var failures: int = 0
	failures += await _case_thin_target_direct()
	failures += await _case_thin_target_rasante()
	failures += await _case_glass_post_onpath()
	failures += await _case_glass_post_rasante()
	failures += await _case_stone_thin_rasante()
	if failures == 0:
		print("BULLET_TUNNELING_TEST: PASS")
	else:
		printerr("BULLET_TUNNELING_TEST: FAIL (%d casos falharam)" % failures)
	quit(failures)


func _make_def(target_pos: Vector2, target_rot: float = 0.0) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = 99
	def.level_number = 4
	def.ammo = 3
	def.target = TargetDefinition.new()
	def.target.position = target_pos
	def.target.rotation_degrees = target_rot
	return def


func _make_ob(id: String, kind: StringName, pos: Vector2, scl: Vector2) -> ObstacleDefinition:
	var ob := ObstacleDefinition.new()
	ob.id = id
	ob.kind = kind
	ob.position = pos
	ob.scale = scl
	return ob


func _shoot(def: LevelDefinition, angle: float, power: float) -> Dictionary:
	return await LevelSolver.simulate_shot(def, LevelSolver.initial_state(def), angle, power, root)


# Alvo fino de frente, potência máxima: todo contato visual registra.
func _case_thin_target_direct() -> int:
	var result := await _shoot(_make_def(Vector2(1000, 326)), 10.0, 1.0)
	if not result["hit_target"]:
		return _fail("thin_target_direct (atravessou sem target_hit)", result)
	return 0


# Alvo deitado (90° → 94.8x28.8, altura < 33px/tick): rasante horizontal
# sobre a lâmina. Era o caso que mais falhava antes (Causa A).
func _case_thin_target_rasante() -> int:
	var def := _make_def(Vector2(1000, 330), 90.0)
	var result := await _shoot(def, 8.0, 1.0)
	if not result["hit_target"]:
		return _fail("thin_target_rasante (atravessou alvo deitado)", result)
	return 0


# Poste de vidro 0.05 (~48x47) cheio na rota: tem que atenuar + shards 0.
func _case_glass_post_onpath() -> int:
	var def := _make_def(Vector2(1000, 326))
	def.obstacles.append(_make_ob("g1", ObstacleDefinition.KIND_GLASS, Vector2(600, 361), Vector2(0.05, 0.05)))
	var result := await _shoot(def, 10.0, 1.0)
	if not ("g1" in (result["destroyed"] as Array)):
		return _fail("glass_post_onpath (atravessou sem *=0.85/shards)", result)
	return 0


# Poste de vidro 0.05 em rasante (corda curta): o HitBox discreto sozinho
# perdia; o raycast da bala (collide_with_areas) tem que pegar.
func _case_glass_post_rasante() -> int:
	var def := _make_def(Vector2(1000, 340))
	def.obstacles.append(_make_ob("g1", ObstacleDefinition.KIND_GLASS, Vector2(650, 352), Vector2(0.05, 0.05)))
	var result := await _shoot(def, 6.0, 1.0)
	var glass_dead := not bool(result["end_state"]["glass_alive"].get("g1", true))
	if not glass_dead and not result["hit_target"]:
		return _fail("glass_post_rasante (silencioso: sem quebra e sem alvo)", result)
	return 0


# Pedra 0.2 em rasante: rebate sem registrar era a discordância da Causa B
# (rebote visível sem hit → HP2 não racha). Aqui o corpo roteia o hit.
func _case_stone_thin_rasante() -> int:
	var def := _make_def(Vector2(1000, 326))
	def.obstacles.append(_make_ob("s1", ObstacleDefinition.KIND_STONE, Vector2(600, 355), Vector2(0.2, 0.2)))
	var result := await _shoot(def, 10.0, 1.0)
	var hp := int(result["end_state"]["stone_hp"].get("s1", -1))
	var rico := int(result["ricochets"])
	# Ou rachou (hp 1) ou o tiro passou por cima e acertou o alvo —
	# o proibido é rebotar (rico ≥ 1) sem registrar (hp segue 2).
	if rico >= 1 and hp == 2:
		return _fail("stone_rasante (rebote sem hit: hp segue 2)", result)
	return 0


func _fail(case_name: String, result: Dictionary) -> int:
	printerr("  [tunneling:%s] hit=%s term=%s rico=%s destroyed=%s frames=%s shards=%s" % [
		case_name, str(result["hit_target"]), str(result["termination"]),
		str(result["ricochets"]), str(result["destroyed"]),
		str(result["frames"]), str(result["shard_count"])])
	return 1
