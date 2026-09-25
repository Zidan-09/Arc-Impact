extends SceneTree
## Teste do DifficultyScorer da Etapa 8 (fórmula, banda, monotonicidade).
## Roda headless, sem física e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/difficulty_scorer_test.gd
## Usa SolutionRecords sintéticos: a curva real com física é calibrada
## pela sonda documentada em DifficultyTable, não aqui.


func _init() -> void:
	var failures: int = 0
	failures += _check_formula()
	failures += _check_stones()
	failures += _check_band()
	failures += _check_monotonic()
	failures += _check_rejects_out_of_band()
	if failures == 0:
		print("DIFFICULTY_SCORER_TEST: PASS")
	else:
		printerr("DIFFICULTY_SCORER_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


func _base_def() -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = 1
	def.level_number = 1
	def.ammo = 3
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1000, 326)
	return def


func _record(shots: int, ricochets: int, margin: float, found: int) -> SolutionRecord:
	var record := SolutionRecord.new()
	record.total_shots = shots
	record.total_ricochets = ricochets
	record.min_angle_margin = margin
	record.solutions_found = found
	record.shots = [{"angle": 10.0, "power": 0.65, "ricochets": ricochets, "destroyed": []}]
	return record


# Tiro aberto típico (medido: 6.2): 1 tiro, 0 ricochetes, margem 0.5,
# 3 soluções, alvo a ~830px => 3 + 0 + 0 + 2 + 0.67 + 0.57 ~= 6.24.
func _check_formula() -> int:
	var total := DifficultyScorer.score(_base_def(), _record(1, 0, 0.5, 3))
	if absf(total - 6.24) > 0.05:
		return _fail("fórmula: %.2f (esperado ~6.24)" % total)
	return 0


# Pedra destruída soma w3=1.5 exatamente uma vez por id.
func _check_stones() -> int:
	var def := _base_def()
	var ob := ObstacleDefinition.new()
	ob.id = "s1"
	ob.kind = ObstacleDefinition.KIND_STONE
	ob.position = Vector2(600, 400)
	def.obstacles.append(ob)
	var record := _record(2, 0, 0.5, 1)
	record.shots = [
		{"angle": 10.0, "power": 0.65, "ricochets": 0, "destroyed": []},
		{"angle": 10.0, "power": 0.65, "ricochets": 0, "destroyed": ["s1"]},
	]
	var total := DifficultyScorer.score(def, record)
	var plain := DifficultyScorer.score(_base_def(), _record(2, 0, 0.5, 1))
	if absf((total - plain) - 1.5) > 0.01:
		return _fail("pedra: delta=%.2f (esperado 1.5)" % (total - plain))
	return 0


func _check_band() -> int:
	var cfg := DifficultyTable.get_config(2) # 0..10
	if not DifficultyScorer.in_band(6.24, cfg):
		return _fail("banda 1-3 deveria aceitar 6.24")
	if DifficultyScorer.in_band(99.0, cfg):
		return _fail("banda 1-3 não deveria aceitar 99")
	return 0


# Mais tiros, mais ricochetes, menos margem, menos soluções => mais score.
func _check_monotonic() -> int:
	var base := DifficultyScorer.score(_base_def(), _record(1, 0, 0.5, 3))
	var checks := [
		DifficultyScorer.score(_base_def(), _record(2, 0, 0.5, 3)) > base,
		DifficultyScorer.score(_base_def(), _record(1, 1, 0.5, 3)) > base,
		DifficultyScorer.score(_base_def(), _record(1, 0, 0.25, 3)) > base,
		DifficultyScorer.score(_base_def(), _record(1, 0, 0.5, 1)) > base,
	]
	for i in checks.size():
		if not checks[i]:
			return _fail("monotonicidade quebrou no caso %d" % i)
	return 0


# Banda impossível rejeita o candidato típico (o gerador cai em fallback).
func _check_rejects_out_of_band() -> int:
	var cfg := DifficultyConfig.new()
	cfg.score_min = 50.0
	cfg.score_max = 60.0
	if DifficultyScorer.in_band(DifficultyScorer.score(_base_def(), _record(1, 0, 0.5, 3)), cfg):
		return _fail("banda 50-60 não deveria aceitar tiro aberto")
	return 0


func _fail(message: String) -> int:
	printerr("  [scorer] " + message)
	return 1
