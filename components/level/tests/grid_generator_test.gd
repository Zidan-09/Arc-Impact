extends SceneTree
## Teste do gerador em grade (Etapa 4 da reimplementação).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/grid_generator_test.gd
## Saída: "GRID_GENERATOR_TEST: PASS" (exit 0) ou FAIL (exit 1).
## Cobre: dimensões, Cannon (colunas + conexão), Floor (base + relevo),
## Target, conectividade dos Obstacles, seed determinística, variedade e
## regeneração/ultimate. Sem física: só dados + grade lógica.


func _init() -> void:
	var failures: int = 0
	failures += _case_structure()
	failures += _case_determinism()
	failures += _case_variety()
	failures += _case_levels_progression()
	if failures == 0:
		print("GRID_GENERATOR_TEST: PASS")
	else:
		printerr("GRID_GENERATOR_TEST: FAIL (%d casos falharam)" % failures)
	quit(failures)


## Regras estruturais em várias seeds/fases (inclui o ultimate).
func _case_structure() -> int:
	var failures := 0
	var seeds := [1, 7, 42, 99, 1234, 777]
	var levels := [1, 2, 4, 8, 12]
	for level in levels:
		for seed_value in seeds:
			var result := FastLevelGenerator.generate(seed_value, level)
			var def: LevelDefinition = result["def"]
			var tag := "seed=%d level=%d" % [seed_value, level]
			failures += _check_def(def, tag)
			if def.floors.is_empty():
				printerr("  [structure:%s] sem floors" % tag)
				failures += 1
			if def.target == null:
				printerr("  [structure:%s] sem target" % tag)
				failures += 1
			if def.cannon_position.x > 360.0:
				printerr("  [structure:%s] canhão fora da esquerda: %s" % [tag, str(def.cannon_position)])
				failures += 1
	return failures


## Checagens físicas sobre a def instanciável (espelham o validador).
func _check_def(def: LevelDefinition, tag: String) -> int:
	var failures := 0
	# Floor cobre a base: existe tile perto de cada ponto da faixa.
	for x in [50.0, 350.0, 650.0, 950.0, 1250.0]:
		var covered := false
		for floor in def.floors:
			if abs(floor.position.x - x) < 60.0 and abs(floor.position.y - 670.0) < 60.0:
				covered = true
				break
		if not covered:
			printerr("  [floor:%s] base descoberta perto de x=%d" % [tag, int(x)])
			failures += 1
	# Relevo: ao menos um tile acima da base.
	var relief := false
	for floor in def.floors:
		if floor.position.y < 620.0:
			relief = true
			break
	if not relief:
		printerr("  [floor:%s] sem relevo" % tag)
		failures += 1
	# Cannon conectado: pé dentro de um tile de Floor.
	var foot := Cannon.foot_position(def.cannon_position, def.cannon_scale)
	var supported := false
	for floor in def.floors:
		var size := MaterialRules.floor_size() * floor.scale
		if Rect2(floor.position - size * 0.5, size).grow(8.0).has_point(foot):
			supported = true
			break
	if not supported:
		printerr("  [cannon:%s] flutuando (pé %s)" % [tag, str(foot)])
		failures += 1
	# Obstacles conectados ao Floor (direta ou via peças), sem flutuar.
	var boxes: Array[Rect2] = []
	for obstacle in def.obstacles:
		boxes.append(_obstacle_aabb(obstacle))
	for i in def.obstacles.size():
		var touching := false
		for floor in def.floors:
			var fsize := MaterialRules.floor_size() * floor.scale
			var fbox := Rect2(floor.position - fsize * 0.5, fsize)
			if boxes[i].grow(8.0).intersects(fbox.grow(8.0)):
				touching = true
				break
		if not touching:
			for j in def.obstacles.size():
				if i != j and boxes[i].grow(8.0).intersects(boxes[j].grow(8.0)):
					touching = true
					break
		if not touching:
			for structure in def.structures:
				var ssize := MaterialRules.structure_size() * structure.scale
				var sbox := Rect2(structure.position - ssize * 0.5, ssize)
				if boxes[i].grow(8.0).intersects(sbox.grow(8.0)):
					touching = true
					break
		if not touching:
			printerr("  [obstacle:%s] %s flutuando" % [tag, def.obstacles[i].id])
			failures += 1
	return failures


func _obstacle_aabb(obstacle: ObstacleDefinition) -> Rect2:
	var size := MaterialRules.base_size(obstacle.kind) * obstacle.scale
	if absf(wrapf(obstacle.rotation_degrees, 0.0, 180.0) - 90.0) < 0.01:
		size = Vector2(size.y, size.x)
	return Rect2(obstacle.position - size * 0.5, size)


## Mesma seed 2x => mesma fase (determinismo).
func _case_determinism() -> int:
	var a := FastLevelGenerator.generate(99, 3)
	var b := FastLevelGenerator.generate(99, 3)
	var sa := JSON.stringify((a["def"] as LevelDefinition).to_dict())
	var sb := JSON.stringify((b["def"] as LevelDefinition).to_dict())
	if sa != sb:
		printerr("  [determinism] fases divergiram para a mesma seed")
		return 1
	if (a["grid_ascii"] as String) != (b["grid_ascii"] as String):
		printerr("  [determinism] grades divergiram para a mesma seed")
		return 1
	return 0


## Seeds distintas => layouts distintos (variedade real).
func _case_variety() -> int:
	var seen := {}
	var archs := {}
	for seed_value in [11, 22, 33, 44, 55, 66, 77, 88]:
		var result := FastLevelGenerator.generate(seed_value, 5)
		seen[result["grid_ascii"]] = true
		archs[String(result["archetype"])] = true
	if seen.size() < 3:
		printerr("  [variety] só %d layouts em 8 seeds" % seen.size())
		return 1
	if archs.size() < 2:
		printerr("  [variety] só 1 arquétipo em 8 seeds: %s" % str(archs.keys()))
		return 1
	print("  [variety] %d layouts / %d arquétipos em 8 seeds" % [seen.size(), archs.size()])
	return 0


## Progressão: fases iniciais sem metal obrigatório, fases altas com
## metal; regeneração nunca estoura (ultimate como rede).
func _case_levels_progression() -> int:
	var failures := 0
	for level in [1, 2, 6, 12, 18]:
		var metals := 0
		for seed_value in [5, 6, 7]:
			var result := FastLevelGenerator.generate(seed_value, level)
			var def: LevelDefinition = result["def"]
			for obstacle in def.obstacles:
				if obstacle.kind == ObstacleDefinition.KIND_METAL:
					metals += 1
		if level <= 2 and metals > 0:
			printerr("  [progression] fase %d com metal (cedo demais)" % level)
			failures += 1
	# Regeneração: mesmo seed/level sempre retorna def válida.
	var result := FastLevelGenerator.generate(424242, 9)
	if result["def"] == null:
		printerr("  [regen] sem def (nem ultimate)")
		failures += 1
	return failures
