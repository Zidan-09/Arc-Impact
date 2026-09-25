extends SceneTree
## Teste de contrato dos dados da Etapa 1 (DoD: round-trip + cobertura).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/level_data_test.gd
## Saída: "LEVEL_DATA_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.


func _init() -> void:
	var failures: int = 0
	failures += _check_full_roundtrip()
	failures += _check_empty_roundtrip()
	failures += _check_table_coverage()
	if failures == 0:
		print("LEVEL_DATA_TEST: PASS")
	else:
		printerr("LEVEL_DATA_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


func _check_full_roundtrip() -> int:
	var def := LevelDefinition.new()
	def.seed = 892301
	def.level_number = 12
	def.ammo = 3
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1000, 200)

	var glass := ObstacleDefinition.new()
	glass.id = "obs_01"
	glass.kind = ObstacleDefinition.KIND_GLASS
	glass.position = Vector2(600, 400)
	def.obstacles.append(glass)

	var stone := ObstacleDefinition.new()
	stone.id = "obs_02"
	stone.kind = ObstacleDefinition.KIND_STONE
	stone.position = Vector2(800, 300)
	stone.rotation_degrees = 90.0
	def.obstacles.append(stone)

	var solution := SolutionRecord.new()
	solution.shots = [{"angle": 45.0, "power": 0.8, "ricochets": 1, "destroyed": ["obs_01"]}]
	solution.total_shots = 1
	solution.total_ricochets = 1
	solution.solutions_found = 3
	solution.min_angle_margin = 1.5
	def.solution = solution

	var first := def.to_dict()
	var second := LevelDefinition.from_dict(first).to_dict()
	if JSON.stringify(first) != JSON.stringify(second):
		printerr("  [full_roundtrip] dicionários divergem.")
		return 1
	return 0


func _check_empty_roundtrip() -> int:
	var def := LevelDefinition.new()
	var first := def.to_dict()
	var rebuilt := LevelDefinition.from_dict(first)
	if rebuilt.target != null or rebuilt.solution != null:
		printerr("  [empty_roundtrip] target/solution deveriam ser nulos.")
		return 1
	if JSON.stringify(first) != JSON.stringify(rebuilt.to_dict()):
		printerr("  [empty_roundtrip] dicionários divergem.")
		return 1
	return 0


func _check_table_coverage() -> int:
	var failures: int = 0
	for level in range(1, 21):
		var cfg := DifficultyTable.get_config(level)
		if cfg.level_number != level:
			printerr("  [table] fase %d retornou level_number %d." % [level, cfg.level_number])
			failures += 1
		if cfg.ammo < 1 or cfg.ammo > 4:
			printerr("  [table] fase %d com ammo=%d fora de 1..4." % [level, cfg.ammo])
			failures += 1
		if not _valid_range(cfg.glass_count) or not _valid_range(cfg.stone_count) or not _valid_range(cfg.metal_count):
			printerr("  [table] fase %d com contagem min>max." % level)
			failures += 1
		if cfg.allowed_archetypes.is_empty():
			printerr("  [table] fase %d sem arquétipos." % level)
			failures += 1
		if cfg.solver_angle_step <= 0.0 or cfg.solver_power_step <= 0.0:
			printerr("  [table] fase %d com passo de grade inválido." % level)
			failures += 1
		if cfg.score_min > cfg.score_max:
			printerr("  [table] fase %d com banda de score invertida." % level)
			failures += 1
	# RN-06: até a 10 sem ricochete obrigatório; 11+ exige ao menos 1.
	for level in range(1, 11):
		if DifficultyTable.get_config(level).required_ricochets_min != 0:
			printerr("  [table] fase %d (≤10) exigindo ricochete." % level)
			failures += 1
	for level in range(11, 21):
		if DifficultyTable.get_config(level).required_ricochets_min < 1:
			printerr("  [table] fase %d (11+) sem ricochete obrigatório." % level)
			failures += 1
	# Limites: fase 0 fixa na banda 1; além da 20 mantém endgame.
	if DifficultyTable.get_config(0).ammo != DifficultyTable.get_config(1).ammo:
		printerr("  [table] fase 0 não fixou na banda inicial.")
		failures += 1
	var over := DifficultyTable.get_config(999)
	if over.level_number != 999 or over.max_obstacles != DifficultyTable.get_config(20).max_obstacles:
		printerr("  [table] fase 999 não reutilizou a banda mais difícil.")
		failures += 1
	return failures


func _valid_range(count: Vector2i) -> bool:
	return count.x <= count.y and count.x >= 0
