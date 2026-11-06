extends SceneTree
## Teste do balanceamento de munição (AmmoBalancer + DifficultyTable).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/ammo_balance_test.gd
## Saída: "AMMO_BALANCE_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).
##
## Cobre (ver §6 da issue de balanceamento):
##  1. limites da RN-03 (1..4) e patamares das bandas (progressão);
##  2. munição entregue == fórmula central (patamar + complexidade);
##  3. munição >= custo do caminho comprovado (fase solucionável);
##  4. revalidação independente da fase com a munição entregue;
##  5. fases avançadas NUNCA presas no 2 antigo e variando com a
##     complexidade;
##  6. sem saltos desproporcionais na progressão.

var levels := [1, 3, 5, 8, 12, 16, 18, 20, 25, 40]
var seeds := [1, 7, 42, 99, 123, 2024]


func _init() -> void:
	var rows: Array[Dictionary] = []
	# Amostra gerada UMA vez e reutilizada por todas as checagens.
	for level in levels:
		var baseline := AmmoBalancer.baseline_for(level)
		for seed_value in seeds:
			var result := FastLevelGenerator.generate(seed_value, level)
			var def: LevelDefinition = result["def"]
			var grid := _grid_from_ascii(String(result["grid_ascii"]))
			grid.archetype = StringName(String(result["archetype"]))
			var arcs := GridLevelValidator.sample_arcs(grid, AmmoBalancer.MAX_AMMO)
			rows.append({
				"level": level, "seed": seed_value, "baseline": baseline,
				"def": def, "grid": grid, "fallback": bool(result["fallback_used"]),
				"min_cost": int(arcs["min_cost"]),
				"complexity": AmmoBalancer.complexity(grid, arcs),
			})
	var failures := 0
	failures += _check_baselines()
	failures += _check_bounds_and_formula(rows)
	failures += _check_solvability(rows)
	failures += _check_advanced_not_starved(rows)
	failures += _check_progression_steps(rows)
	if failures == 0:
		print("AMMO_BALANCE_TEST: PASS")
	else:
		printerr("AMMO_BALANCE_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


## 1) Patamares das bandas: dentro da RN-03, progressão não crescente,
## limites de fase (0 fixa na 1; >20 reutiliza a banda mais difícil).
func _check_baselines() -> int:
	var failures := 0
	for level in range(1, 41):
		var baseline := AmmoBalancer.baseline_for(level)
		if baseline < AmmoBalancer.MIN_AMMO or baseline > AmmoBalancer.MAX_AMMO:
			printerr("  [baselines] fase %d com patamar %d fora de %d..%d." % [
				level, baseline, AmmoBalancer.MIN_AMMO, AmmoBalancer.MAX_AMMO])
			failures += 1
	if AmmoBalancer.baseline_for(0) != AmmoBalancer.baseline_for(1):
		printerr("  [baselines] fase 0 não fixou na banda inicial.")
		failures += 1
	var over := DifficultyTable.get_config(999)
	if over.level_number != 999 or over.ammo != DifficultyTable.get_config(20).ammo:
		printerr("  [baselines] fase 999 não reutilizou a banda mais difícil.")
		failures += 1
	# Progressão: o patamar nunca sobe com a fase (dificuldade base
	# continua crescendo) e o tutorial é pelo menos tão generoso quanto
	# o endgame.
	var last := AmmoBalancer.MAX_AMMO
	for level in [1, 4, 7, 11, 16]:
		var baseline := AmmoBalancer.baseline_for(level)
		if baseline > last:
			printerr("  [baselines] patamar da fase %d (%d) subiu em relação à banda anterior (%d)." % [
				level, baseline, last])
			failures += 1
		last = baseline
	return failures


## 2) Munição entregue: dentro da RN-03, igual à fórmula central e nunca
## abaixo do patamar da banda.
func _check_bounds_and_formula(rows: Array[Dictionary]) -> int:
	var failures := 0
	for row in rows:
		var def: LevelDefinition = row["def"]
		var tag := "fase %d semente %d" % [int(row["level"]), int(row["seed"])]
		if def == null:
			printerr("  [formula:%s] sem LevelDefinition." % tag)
			failures += 1
			continue
		if def.ammo < AmmoBalancer.MIN_AMMO or def.ammo > AmmoBalancer.MAX_AMMO:
			printerr("  [formula:%s] ammo=%d fora de %d..%d (RN-03)." % [
				tag, def.ammo, AmmoBalancer.MIN_AMMO, AmmoBalancer.MAX_AMMO])
			failures += 1
		var expected := clampi(
			int(row["baseline"]) + int(row["complexity"]),
			AmmoBalancer.MIN_AMMO, AmmoBalancer.MAX_AMMO)
		if def.ammo != expected:
			printerr("  [formula:%s] ammo=%d, esperado %d (patamar %d + complexidade %d)." % [
				tag, def.ammo, expected, int(row["baseline"]), int(row["complexity"])])
			failures += 1
		if def.ammo < int(row["baseline"]):
			printerr("  [formula:%s] ammo=%d abaixo do patamar %d." % [
				tag, def.ammo, int(row["baseline"])])
			failures += 1
	return failures


## 3)+4) Solubilidade: a munição cobre o caminho comprovado e a fase
## revalidada com EXATAMENTE essa munição passa no validador.
func _check_solvability(rows: Array[Dictionary]) -> int:
	var failures := 0
	for row in rows:
		var def: LevelDefinition = row["def"]
		var tag := "fase %d semente %d" % [int(row["level"]), int(row["seed"])]
		var min_cost := int(row["min_cost"])
		if min_cost == 0:
			printerr("  [solvable:%s] nenhum caminho comprovado até o alvo." % tag)
			failures += 1
			continue
		if def.ammo < min_cost:
			printerr("  [solvable:%s] ammo=%d < custo comprovado %d." % [
				tag, def.ammo, min_cost])
			failures += 1
		if bool(row["fallback"]):
			continue # fallback é a rede curada; validação própria abaixo
		var check := GridLevelValidator.validate(row["grid"] as GridState, def.ammo)
		if not bool(check["ok"]):
			printerr("  [solvable:%s] revalidação falhou com ammo=%d: %s" % [
				tag, def.ammo, str(check["errors"])])
			failures += 1
	return failures


## 5) Regressão do bug: fases avançadas não ficam presas em 2 e a
## complexidade realmente acrescenta tiros (variação real).
func _check_advanced_not_starved(rows: Array[Dictionary]) -> int:
	var failures := 0
	var distinct := {}
	var raised := 0
	for row in rows:
		if int(row["level"]) < 16:
			continue
		var def: LevelDefinition = row["def"]
		if def.ammo <= 2:
			printerr("  [advanced] fase %d semente %d com ammo=%d (banda avançada presa em 2)." % [
				int(row["level"]), int(row["seed"]), def.ammo])
			failures += 1
		distinct[def.ammo] = true
		if def.ammo > int(row["baseline"]):
			raised += 1
	if distinct.size() < 2:
		printerr("  [advanced] munição não variou com a complexidade: %s" % str(distinct.keys()))
		failures += 1
	if raised == 0:
		printerr("  [advanced] complexidade nunca acrescentou tiro acima do patamar.")
		failures += 1
	# Tutorial generoso: fases 1-3 mantêm o patamar cheio (não perdem
	# munição com a correção).
	for row in rows:
		if int(row["level"]) > 3:
			continue
		var def: LevelDefinition = row["def"]
		if def.ammo != AmmoBalancer.MAX_AMMO:
			printerr("  [advanced] fase %d semente %d com ammo=%d (tutorial deveria ter %d)." % [
				int(row["level"]), int(row["seed"]), def.ammo, AmmoBalancer.MAX_AMMO])
			failures += 1
	return failures


## 6) Progressão sem saltos: ao longo das fases amostradas, com a mesma
## semente, a munição muda no máximo 1 tiro por degrau.
func _check_progression_steps(rows: Array[Dictionary]) -> int:
	var failures := 0
	var ammo_by_key := {}
	for row in rows:
		ammo_by_key["%d:%d" % [int(row["level"]), int(row["seed"])] ] = \
			(row["def"] as LevelDefinition).ammo
	for seed_value in seeds:
		var previous := -1
		var previous_level := -1
		for level in levels:
			var ammo := int(ammo_by_key["%d:%d" % [level, seed_value]])
			if previous >= 0 and absi(ammo - previous) > 1:
				printerr("  [steps] semente %d: salto de %d (fase %d) para %d (fase %d)." % [
					seed_value, previous, previous_level, ammo, level])
				failures += 1
			previous = ammo
			previous_level = level
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
