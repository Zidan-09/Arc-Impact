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
	failures += _check_table_coverage() # inclui curva crescente (Etapa 8)
	failures += _check_intent_roundtrip() # Etapa 1 (composition-first)
	failures += _check_v1_compat() # Etapa 1 (dicts legados sem as chaves)
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
		# Etapa 9: física em tempo real (~745ms/sim) impõe grade grossa
		# na v1; grade fina volta com física acelerada.
		if cfg.solver_angle_step != 10.0 or cfg.solver_power_step != 0.35:
			printerr("  [table] fase %d fora da grade v1 (10 x 0.35)." % level)
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
	# Etapa 8 (DoD: curva crescente): teto e piso das bandas sobem com
	# a fase; fases 1-3 aceitam tiro direto (teto >= 6.3 medido) e o
	# endgame exige mais (piso 16+ > piso 1-3).
	var floors := [1, 4, 7, 11, 16]
	var last_min := -1.0
	var last_max := -1.0
	for level in floors:
		var cfg := DifficultyTable.get_config(level)
		if cfg.score_min < last_min or cfg.score_max < last_max:
			printerr("  [table] banda da fase %d regrediu (curva deve subir)." % level)
			failures += 1
		last_min = cfg.score_min
		last_max = cfg.score_max
	if DifficultyTable.get_config(1).score_max < 6.3:
		printerr("  [table] banda 1-3 rejeitaria tiro direto típico (6.2).")
		failures += 1
	if DifficultyTable.get_config(16).score_min <= DifficultyTable.get_config(1).score_min:
		printerr("  [table] endgame sem piso mais alto que a banda inicial.")
		failures += 1
	return failures


func _valid_range(count: Vector2i) -> bool:
	return count.x <= count.y and count.x >= 0


## Etapa 1: intenção (rotação/função do alvo, papéis dos obstáculos,
## floors, structures, pose do canhão, tags) sobrevive ao round-trip.
func _check_intent_roundtrip() -> int:
	var def := LevelDefinition.new()
	def.seed = 11
	def.level_number = 5
	def.ammo = 3
	def.cannon_position = Vector2(200, 465)
	def.cannon_scale = Vector2(0.3, 0.3)
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1150, 590)
	def.target.rotation_degrees = 90.0
	def.target.role = &"foot"
	var floor := FloorDefinition.new()
	floor.position = Vector2(150, 570)
	def.floors.append(floor)
	var beam := StructureDefinition.new()
	beam.id = "struct_01"
	beam.position = Vector2(1010, 344)
	beam.rotation_degrees = 90.0
	beam.role = StructureDefinition.ROLE_BEAM
	beam.link_a = "obs_01"
	beam.link_b = "obs_02"
	def.structures.append(beam)
	var gate := ObstacleDefinition.new()
	gate.id = "obs_01"
	gate.kind = ObstacleDefinition.KIND_GLASS
	gate.position = Vector2(950, 455)
	gate.scale = Vector2(0.1, 0.1)
	gate.group = &"gate"
	gate.role = "joint"
	gate.anchor = "floor"
	gate.mechanic = &"breakable"
	def.obstacles.append(gate)
	def.composition_tags = [&"platform", &"gate"]
	var first := def.to_dict()
	var rebuilt := LevelDefinition.from_dict(first)
	if JSON.stringify(first) != JSON.stringify(rebuilt.to_dict()):
		printerr("  [intent_roundtrip] dicionários divergem.")
		return 1
	if rebuilt.target.rotation_degrees != 90.0 or rebuilt.target.role != &"foot":
		printerr("  [intent_roundtrip] alvo perdeu rotação/função.")
		return 1
	if rebuilt.cannon_scale != Vector2(0.3, 0.3) or rebuilt.floors.size() != 1:
		printerr("  [intent_roundtrip] canhão/floor perderam dados.")
		return 1
	if rebuilt.structures.size() != 1 or rebuilt.structures[0].link_b != "obs_02":
		printerr("  [intent_roundtrip] structure perdeu papel/ligação.")
		return 1
	if rebuilt.obstacles[0].mechanic != &"breakable":
		printerr("  [intent_roundtrip] obstáculo perdeu função mecânica.")
		return 1
	return 0


## Etapa 1: dicts serializados na v1 (sem floors/structures/tags/escala
## do canhão/rotação do alvo) desserializam com os padrões legados.
func _check_v1_compat() -> int:
	var legacy := {
		"seed": 7, "generator_version": 1, "level_number": 2, "ammo": 2,
		"cannon_position": {"x": 173.0, "y": 523.0},
		"target": {"position": {"x": 1000.0, "y": 200.0}, "size": {"x": 80.0, "y": 80.0}},
		"obstacles": [
			{"id": "obs_01", "kind": "glass",
				"position": {"x": 600.0, "y": 400.0}, "rotation_degrees": 0.0,
				"scale": {"x": 0.1, "y": 0.1}},
		],
	}
	var def := LevelDefinition.from_dict(legacy)
	if def.generator_version != 1 or def.cannon_scale != Vector2(0.16, 0.16):
		printerr("  [v1_compat] versão/escala do canhão divergem.")
		return 1
	if not def.floors.is_empty() or not def.structures.is_empty():
		printerr("  [v1_compat] fase legada deveria vir sem floors/structures.")
		return 1
	if def.target.rotation_degrees != 0.0 or def.obstacles[0].mechanic != &"frame":
		printerr("  [v1_compat] padrões de intenção divergem.")
		return 1
	if JSON.stringify(def.to_dict()["obstacles"]) == "":
		printerr("  [v1_compat] obstáculos legados se perderam.")
		return 1
	return 0
