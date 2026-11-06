extends SceneTree
## Sonda de diagnóstico do balanceamento de munição (AmoBalancer).
##
## Para cada fase/seed mostra: patamar da banda, complexidade medida no
## cenário gerado (custo do caminho + rota indireta), munição final
## entregue e a composição de obstáculos. Confirma que a munição varia
## com a complexidade e que nenhum candidato cai abaixo do patamar.
## Uso: godot --headless --path . -s res://components/level/tests/ammo_probe.gd [-- 16 17]


func _init() -> void:
	var levels := [1, 3, 5, 8, 12, 16, 18, 20, 25, 40]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		levels = []
		for a in args:
			levels.append(int(a))
	var seeds := [1, 7, 42, 99, 123, 2024, 5, 999]
	print("level | seed | patamar | min_cost | complexidade | ammo_final | obs(g/s/m) | fallback | rejects")
	var hist := {}
	for level in levels:
		var baseline := AmmoBalancer.baseline_for(level)
		for seed_value in seeds:
			var result := FastLevelGenerator.generate(seed_value, level)
			var def: LevelDefinition = result["def"]
			var grid := _grid_from_ascii(String(result["grid_ascii"]))
			grid.archetype = StringName(String(result["archetype"]))
			var arcs := GridLevelValidator.sample_arcs(grid, AmmoBalancer.MAX_AMMO)
			var counts := _materials(grid)
			var rejects := 0
			for line in Array(result["log"]):
				if String(line).begins_with("reject:"):
					rejects += 1
			var key := "%d->%d" % [level, def.ammo]
			hist[key] = int(hist.get(key, 0)) + 1
			print("%d | %d | %d | %d | +%d | %d | %d/%d/%d | %s | %d" % [
				level, seed_value, baseline, int(arcs["min_cost"]),
				AmmoBalancer.complexity(grid, arcs), def.ammo,
				counts.x, counts.y, counts.z,
				str(result["fallback_used"]), rejects])
	print("--- histograma (fase->ammo final) ---")
	for k in hist:
		print("%s : %d" % [String(k), int(hist[k])])
	quit(0)


func _materials(grid: GridState) -> Vector3i:
	var g := 0
	var s := 0
	var m := 0
	for row in grid.rows:
		for col in grid.cols:
			match grid.get_cell(col, row):
				GridState.Cell.GLASS:
					g += 1
				GridState.Cell.STONE:
					s += 1
				GridState.Cell.METAL:
					m += 1
	return Vector3i(g, s, m)


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
