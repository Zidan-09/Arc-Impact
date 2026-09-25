extends SceneTree
## Teste do solve() BFS da Etapa 5 (DoD parcial: 1 tiro, 2 tiros e nulo).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/solver_test.gd
## Grade propositalmente grossa (10° x 0.35) para caber em tempo de teste;
## a calibragem fina da grade é Etapa 9. Imprime ms e nº de simulações
## por caso (métrica de custo do DoD).
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.


func _initialize() -> void:
	super._initialize()
	Engine.time_scale = 8.0
	_run_all() # async: segue nos physics_frames e termina com quit()


func _run_all() -> void:
	var failures: int = 0
	failures += await _case_single_shot()
	failures += await _case_two_shot()
	failures += await _case_impossible()
	Engine.time_scale = 1.0
	if failures == 0:
		print("SOLVER_TEST: PASS")
	else:
		printerr("SOLVER_TEST: FAIL (%d casos falharam)" % failures)
	quit(failures)


func _coarse_cfg() -> DifficultyConfig:
	var cfg := DifficultyConfig.new()
	cfg.solver_angle_step = 10.0
	cfg.solver_power_step = 0.35
	return cfg


func _make_ob(id: String, kind: StringName, pos: Vector2, scl: Vector2) -> ObstacleDefinition:
	var ob := ObstacleDefinition.new()
	ob.id = id
	ob.kind = kind
	ob.position = pos
	ob.scale = scl
	return ob


# Tiro aberto: solução em 1 tiro (ângulo 10°, potência 1.0 estão na grade).
func _case_single_shot() -> int:
	var def := LevelDefinition.new()
	def.ammo = 1
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1000, 326)
	var sims := [0]
	var start := Time.get_ticks_msec()
	var record := await LevelSolver.solve(def, _coarse_cfg(), root, 3, sims)
	var elapsed := Time.get_ticks_msec() - start
	print("  [single] ms=%d sims=%d" % [elapsed, sims[0]])
	if record == null:
		return _fail("single (sem solução)")
	if record.total_shots != 1:
		return _fail("single (shots=%d)" % record.total_shots)
	if record.shots[0]["angle"] != 10.0 or record.shots[0]["power"] != 1.0:
		return _fail("single (tiro=%s)" % str(record.shots[0]))
	if record.solutions_found < 1:
		return _fail("single (solutions_found)")
	print("  [single] margin=%s ricochets=%d" % [str(record.min_angle_margin), record.total_ricochets])
	return 0


# Alvo em U de metal com a boca bloqueada por pedra: 1º tiro racha,
# 2º destrói e atravessa até o alvo. Exige profundidade 2.
func _case_two_shot() -> int:
	var def := _u_def(ObstacleDefinition.KIND_STONE)
	def.ammo = 2
	var sims := [0]
	var start := Time.get_ticks_msec()
	var record := await LevelSolver.solve(def, _coarse_cfg(), root, 3, sims)
	var elapsed := Time.get_ticks_msec() - start
	print("  [two] ms=%d sims=%d" % [elapsed, sims[0]])
	if record == null:
		return _fail("two (sem solução)")
	if record.total_shots != 2:
		return _fail("two (shots=%d, esperado 2)" % record.total_shots)
	if record.solutions_found < 1:
		return _fail("two (solutions_found)")
	print("  [two] margin=%s ricochets=%d destroyed=%s" % [
		str(record.min_angle_margin), record.total_ricochets, str(record.shots[1].get("destroyed", []))])
	return 0


# U fechado com metal na boca: inalcançável com 1 tiro => null.
func _case_impossible() -> int:
	var def := _u_def(ObstacleDefinition.KIND_METAL)
	def.ammo = 1
	var sims := [0]
	var start := Time.get_ticks_msec()
	var record := await LevelSolver.solve(def, _coarse_cfg(), root, 3, sims)
	var elapsed := Time.get_ticks_msec() - start
	print("  [impossible] ms=%d sims=%d" % [elapsed, sims[0]])
	if record != null:
		return _fail("impossible (solução inesperada: %s)" % str(record.shots))
	return 0


## U de metal (cima/baixo/direita) com a boca (esquerda, lado do canhão)
## bloqueada por `plug_kind` em (700, 360). Alvo em (900, 360).
func _u_def(plug_kind: StringName) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.target = TargetDefinition.new()
	def.target.position = Vector2(900, 360)
	var metal := Vector2(0.2, 0.2)
	def.obstacles.append(_make_ob("top", ObstacleDefinition.KIND_METAL, Vector2(900, 180), metal))
	def.obstacles.append(_make_ob("bottom", ObstacleDefinition.KIND_METAL, Vector2(900, 540), metal))
	def.obstacles.append(_make_ob("right", ObstacleDefinition.KIND_METAL, Vector2(1080, 360), metal))
	def.obstacles.append(_make_ob("plug", plug_kind, Vector2(700, 360), Vector2(0.3, 0.3)))
	return def


func _fail(message: String) -> int:
	printerr("  [solver] " + message)
	return 1
