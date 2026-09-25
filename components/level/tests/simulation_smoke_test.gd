extends SceneTree
## Teste de fumaça do tiro único (Etapa 4, DoD parcial: 10 defs manuais).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/simulation_smoke_test.gd
## Acelera com Engine.time_scale = 8 (passo fixo de 60 ticks: a sequência
## de integração é a mesma, só avança mais passos por frame real).
## A comparação assistida com o jogo manual (ver o tiro no editor) fica
## como verificação humana; aqui valem invariantes + casos de acerto
## calculados pela balística (origem no muzzle, v0 = 2000 * power).
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.


func _initialize() -> void:
	super._initialize()
	Engine.time_scale = 8.0
	_run_all() # async: segue nos physics_frames e termina com quit()


func _run_all() -> void:
	var failures: int = 0
	failures += await _case_open_direct_hit()
	failures += await _case_open_overshoot()
	failures += await _case_glass_offpath()
	failures += await _case_glass_onpath()
	failures += await _case_metal_ricochet()
	failures += await _case_stone_crack()
	failures += await _case_low_power()
	failures += await _case_glass_then_target()
	failures += await _case_high_arc()
	failures += await _case_dive_down()
	Engine.time_scale = 1.0
	if failures == 0:
		print("SIMULATION_SMOKE_TEST: PASS")
	else:
		printerr("SIMULATION_SMOKE_TEST: FAIL (%d casos falharam)" % failures)
	quit(failures)


func _make_def(target_pos: Vector2) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = 1
	def.level_number = 1
	def.ammo = 3
	def.target = TargetDefinition.new()
	def.target.position = target_pos
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


# Tiro aberto que cruza o alvo (y ~= 326 em x = 1000): deve acertar.
func _case_open_direct_hit() -> int:
	var result := await _shoot(_make_def(Vector2(1000, 326)), 10.0, 1.0)
	if not result["hit_target"] or result["termination"] != "target":
		return _fail("open_direct_hit", result)
	return 0


# Mesmo layout, 60°: passa por cima e sai do cenário.
func _case_open_overshoot() -> int:
	var result := await _shoot(_make_def(Vector2(1000, 326)), 60.0, 1.0)
	if result["hit_target"]:
		return _fail("open_overshoot", result)
	return 0


# Vidro longe da trajetória (y = 100, rota passa a ~360): acerta e poupa o vidro.
func _case_glass_offpath() -> int:
	var def := _make_def(Vector2(1000, 326))
	def.obstacles.append(_make_ob("g1", ObstacleDefinition.KIND_GLASS, Vector2(600, 100), Vector2(0.1, 0.1)))
	var result := await _shoot(def, 10.0, 1.0)
	if not result["hit_target"]:
		return _fail("glass_offpath", result)
	if not bool(result["end_state"]["glass_alive"].get("g1", false)):
		return _fail("glass_offpath (vidro não deveria quebrar)", result)
	if not (result["destroyed"] as Array).is_empty():
		return _fail("glass_offpath (destroyed deveria estar vazio)", result)
	return 0


# Vidro sobre a trajetória: tem que quebrar. Sem estilhaços na sim.
func _case_glass_onpath() -> int:
	var def := _make_def(Vector2(1000, 326))
	def.obstacles.append(_make_ob("g1", ObstacleDefinition.KIND_GLASS, Vector2(600, 361), Vector2(0.1, 0.1)))
	var result := await _shoot(def, 10.0, 1.0)
	if not ("g1" in (result["destroyed"] as Array)):
		return _fail("glass_onpath", result)
	if int(result["shard_count"]) != 0:
		return _fail("glass_onpath (shards na sim)", result)
	return 0


# Metal cheio na rota: rebate (conta ricochete), sem estilhaços.
func _case_metal_ricochet() -> int:
	var def := _make_def(Vector2(1000, 326))
	def.obstacles.append(_make_ob("m1", ObstacleDefinition.KIND_METAL, Vector2(600, 361), Vector2(0.2, 0.2)))
	var result := await _shoot(def, 10.0, 1.0)
	if int(result["ricochets"]) < 1:
		return _fail("metal_ricochet", result)
	if int(result["shard_count"]) != 0:
		return _fail("metal_ricochet (shards na sim)", result)
	return 0


# Pedra na rota, 1 tiro: racha (hp 2 -> 1), não destrói.
func _case_stone_crack() -> int:
	var def := _make_def(Vector2(1000, 326))
	def.obstacles.append(_make_ob("s1", ObstacleDefinition.KIND_STONE, Vector2(600, 361), Vector2(0.2, 0.2)))
	var result := await _shoot(def, 10.0, 1.0)
	if int(result["end_state"]["stone_hp"].get("s1", -1)) != 1:
		return _fail("stone_crack", result)
	if not (result["destroyed"] as Array).is_empty():
		return _fail("stone_crack (não deveria destruir)", result)
	return 0


# Potência mínima: cai antes do alvo.
func _case_low_power() -> int:
	var result := await _shoot(_make_def(Vector2(1000, 326)), 10.0, 0.3)
	if result["hit_target"]:
		return _fail("low_power", result)
	return 0


# Vidro perto do alvo, sobre a rota: tem que quebrar ao passar.
func _case_glass_then_target() -> int:
	var def := _make_def(Vector2(1000, 326))
	def.obstacles.append(_make_ob("g1", ObstacleDefinition.KIND_GLASS, Vector2(900, 331), Vector2(0.1, 0.1)))
	var result := await _shoot(def, 10.0, 1.0)
	if not ("g1" in (result["destroyed"] as Array)):
		return _fail("glass_then_target", result)
	return 0


# Arco alto 30°/0.8 que desce no alvo (y ~= 324 em x = 1000).
func _case_high_arc() -> int:
	var result := await _shoot(_make_def(Vector2(1000, 324)), 30.0, 0.8)
	if not result["hit_target"]:
		return _fail("high_arc", result)
	return 0


# Mira para baixo (-20°): mergulha e sai por baixo, sem acerto.
func _case_dive_down() -> int:
	var result := await _shoot(_make_def(Vector2(1000, 326)), -20.0, 1.0)
	if result["hit_target"]:
		return _fail("dive_down", result)
	return 0


func _fail(case_name: String, result: Dictionary) -> int:
	printerr("  [smoke:%s] hit=%s term=%s rico=%s destroyed=%s frames=%s shards=%s" % [
		case_name, str(result["hit_target"]), str(result["termination"]),
		str(result["ricochets"]), str(result["destroyed"]),
		str(result["frames"]), str(result["shard_count"])])
	return 1
