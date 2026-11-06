extends SceneTree
## Sonda temporária de investigação: gera fases e mostra por que o
## validador as aceitou (arquétipo, munição, métricas balísticas).
## Uso: godot --headless --path . -s res://components/level/tests/winnability_probe.gd


func _init() -> void:
	var levels := [17]
	if OS.get_cmdline_user_args().size() > 0:
		levels = []
		for a in OS.get_cmdline_user_args():
			levels.append(int(a))
	var seeds := [1, 17, 42, 7, 123, 2024, 5, 99]
	for level in levels:
		var cfg := DifficultyTable.get_config(level)
		print("=== level %d (patamar=%d) ===" % [level, cfg.ammo])
		for seed_value in seeds:
			var result := FastLevelGenerator.generate(seed_value, level)
			var def: LevelDefinition = result["def"]
			var ascii := String(result["grid_ascii"])
			var grid := _grid_from_ascii(ascii)
			grid.archetype = StringName(String(result["archetype"]))
			print("--- seed=%d arch=%s ammo=%d fallback=%s candidates=%s" % [
				seed_value, String(result["archetype"]), def.ammo,
				str(result["fallback_used"]), str(result["candidates"])])
			var check := GridLevelValidator.validate(grid, def.ammo)
			var arcs := GridLevelValidator.sample_arcs(grid, def.ammo)
			print(ascii)
			print("  log=%s" % str(result["log"]))
			print("  validate ok=%s errors=%s" % [str(check["ok"]), str(check["errors"])])
			print("  arcs reachable=%d viable=%d clean=%d high_total=%d high_reachable=%d high_viable=%d high_clean=%d" % [
				int(arcs["reachable"]), int(arcs["viable"]), int(arcs["clean"]),
				int(arcs["high_total"]), int(arcs["high_reachable"]),
				int(arcs["high_viable"]), int(arcs["high_clean"])])
	quit(0)


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
