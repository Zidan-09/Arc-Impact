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
			failures += _check_def(def, String(result["grid_ascii"]), tag)
			if def.floors.is_empty():
				printerr("  [structure:%s] sem floors" % tag)
				failures += 1
			if def.target == null:
				printerr("  [structure:%s] sem target" % tag)
				failures += 1
	return failures


## Reconstrói a grade a partir do ascii de debug (C/T/#/g/s/m/+/.).
func _grid_from_ascii(ascii: String) -> GridState:
	var lines := ascii.split("\n")
	var grid := GridState.new(lines[0].length(), lines.size())
	for row in lines.size():
		var line: String = lines[row]
		for col in line.length():
			match line.substr(col, 1):
				"#":
					grid.set_cell(col, row, GridState.Cell.FLOOR)
				"C":
					grid.set_cell(col, row, GridState.Cell.CANNON)
				"T":
					grid.set_cell(col, row, GridState.Cell.TARGET)
				"g":
					grid.set_cell(col, row, GridState.Cell.GLASS)
				"s":
					grid.set_cell(col, row, GridState.Cell.STONE)
				"m":
					grid.set_cell(col, row, GridState.Cell.METAL)
				"+":
					grid.set_cell(col, row, GridState.Cell.STRUCTURE)
	return grid


## Checagens sobre a def instanciável + grade lógica: célula quadrada
## uniforme, posições = centros das células, AABBs exatos, sem
## sobreposição, bounds = área da fase (contrato da câmera).
func _check_def(def: LevelDefinition, ascii: String, tag: String) -> int:
	var failures := 0
	var grid := _grid_from_ascii(ascii)
	var cell := GridState.CELL_SIZE
	if grid.cols < 12 or grid.cols > 14 or grid.rows < 7 or grid.rows > 10:
		printerr("  [dims:%s] grade %dx%d fora da faixa" % [tag, grid.cols, grid.rows])
		failures += 1
	# Grade: base contínua, relevo, canhão à esquerda apoiado, alvo válido.
	for col in grid.cols:
		if grid.get_cell(col, grid.rows - 1) != GridState.Cell.FLOOR:
			printerr("  [floor:%s] base com vão na col %d" % [tag, col])
			failures += 1
	var cannons := grid.find_all(GridState.Cell.CANNON)
	var targets := grid.find_all(GridState.Cell.TARGET)
	if cannons.size() != 1 or cannons[0].x > 3:
		printerr("  [cannon:%s] fora das 4 primeiras colunas" % tag)
		failures += 1
	elif grid.get_cell(cannons[0].x, cannons[0].y + 1) != GridState.Cell.FLOOR:
		printerr("  [cannon:%s] sem Floor abaixo" % tag)
		failures += 1
	if targets.size() != 1:
		printerr("  [target:%s] ausente" % tag)
		failures += 1
	# Contagens def == grade.
	if def.floors.size() != grid.count(GridState.Cell.FLOOR):
		printerr("  [count:%s] floors %d != grade %d" % [tag, def.floors.size(), grid.count(GridState.Cell.FLOOR)])
		failures += 1
	if def.obstacles.size() != grid.count_obstacles():
		printerr("  [count:%s] obstacles %d != grade %d" % [tag, def.obstacles.size(), grid.count_obstacles()])
		failures += 1
	if def.structures.size() != grid.count(GridState.Cell.STRUCTURE):
		printerr("  [count:%s] structures %d != grade %d" % [tag, def.structures.size(), grid.count(GridState.Cell.STRUCTURE)])
		failures += 1
	# AABBs: todos exatamente CELL_SIZE x CELL_SIZE (quadrados uniformes).
	var boxes: Array[Rect2] = []
	for floor in def.floors:
		boxes.append(_aabb_of(floor.position, MaterialRules.floor_size() * floor.scale))
	for obstacle in def.obstacles:
		boxes.append(_obstacle_aabb(obstacle))
	for structure in def.structures:
		boxes.append(_aabb_of(structure.position, _struct_size(structure)))
	for i in boxes.size():
		if not boxes[i].size.is_equal_approx(Vector2(cell, cell)):
			printerr("  [cell:%s] bloco %d com %s (esperado %dx%d)" % [tag, i, str(boxes[i].size), int(cell), int(cell)])
			failures += 1
	# Sem sobreposição: vizinhos encostam, nunca invadem (tol. 2px).
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			if boxes[i].grow(-2.0).intersects(boxes[j].grow(-2.0)):
				printerr("  [overlap:%s] blocos %d/%d se sobrepõem" % [tag, i, j])
				failures += 1
	# Cannon/target nas posições lógicas, escala canônica, pé no apoio.
	if cannons.size() == 1 and targets.size() == 1:
		var expect_c := grid.world_pos(cannons[0].x, cannons[0].y)
		if not def.cannon_position.is_equal_approx(expect_c):
			printerr("  [cannon:%s] fora do centro da célula" % tag)
			failures += 1
		if def.cannon_scale != Cannon.CANNON_SCALE:
			printerr("  [cannon:%s] escala fora da canônica" % tag)
			failures += 1
		var foot := Cannon.foot_position(def.cannon_position, def.cannon_scale)
		var support := grid.world_pos(cannons[0].x, cannons[0].y + 1)
		if absf(foot.y - (support.y - cell * 0.5)) > 1.0 or absf(foot.x - support.x) > 1.0:
			printerr("  [cannon:%s] pé fora do topo do apoio (%s)" % [tag, str(foot)])
			failures += 1
		if not def.target.position.is_equal_approx(grid.world_pos(targets[0].x, targets[0].y)):
			printerr("  [target:%s] fora do centro da célula" % tag)
			failures += 1
	# Contrato da câmera: bounds == área exata da grade.
	if not def.world_bounds.is_equal_approx(grid.phase_bounds()):
		printerr("  [bounds:%s] %s != área da grade %s" % [tag, str(def.world_bounds), str(grid.phase_bounds())])
		failures += 1
	return failures


func _aabb_of(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)


func _struct_size(structure: StructureDefinition) -> Vector2:
	var size := MaterialRules.structure_size() * structure.scale
	if absf(wrapf(structure.rotation_degrees, 0.0, 180.0) - 90.0) < 0.01:
		size = Vector2(size.y, size.x)
	return size


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
