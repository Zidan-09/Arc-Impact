extends SceneTree
## Teste do gerador da Etapa 6 (DoD: determinismo, aprovação, fallback).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/generator_test.gd
## Usa config enxuta com grade grossa (10° x 0.35) para caber em tempo
## de teste; a curva real 1-20 já é coberta pelo level_data_test.
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.


func _initialize() -> void:
	Engine.time_scale = 1.0
	_run_all() # async: segue nos physics_frames e termina com quit()


func _run_all() -> void:
	await physics_frame
	var failures: int = 0
	failures += await _case_determinism()
	failures += await _case_accepts_easy()
	failures += await _case_ricochet_fallback()
	failures += await _case_variety()
	Engine.time_scale = 1.0
	if failures == 0:
		print("GENERATOR_TEST: PASS")
	else:
		printerr("GENERATOR_TEST: FAIL (%d casos falharam)" % failures)
	quit(failures)


## Config de teste: só tiro aberto, poucos vidros, grade grossa.
func _test_cfg() -> DifficultyConfig:
	var cfg := DifficultyConfig.new()
	cfg.level_number = 2
	cfg.ammo = 2
	cfg.max_obstacles = 2
	cfg.glass_count = Vector2i(0, 2)
	cfg.stone_count = Vector2i(0, 0)
	cfg.metal_count = Vector2i(0, 0)
	cfg.required_ricochets_min = 0
	cfg.allowed_archetypes = [&"open_shot"]
	cfg.solver_angle_step = 10.0
	cfg.solver_power_step = 0.35
	cfg.score_min = 0.0
	cfg.score_max = 12.0
	return cfg


# Mesma seed 2x: dicionários idênticos (fase + solução).
func _case_determinism() -> int:
	var first := await ProceduralLevelGenerator.generate(99, 2, root, 10, _test_cfg())
	var second := await ProceduralLevelGenerator.generate(99, 2, root, 10, _test_cfg())
	var a := JSON.stringify((first["def"] as LevelDefinition).to_dict())
	var b := JSON.stringify((second["def"] as LevelDefinition).to_dict())
	print("  [determinism] candidates=%s sims=%s ms=%s fallback=%s" % [
		str(first["candidates"]), str(first["sims"]), str(first["ms"]), str(first["fallback_used"])])
	if a != b:
		return _fail("determinism (fases divergiram)")
	return 0


# Caso fácil: aprova sem fallback, solução dentro da munição.
func _case_accepts_easy() -> int:
	var result := await ProceduralLevelGenerator.generate(7, 2, root, 10, _test_cfg())
	var def: LevelDefinition = result["def"]
	if def == null:
		return _fail("accepts (sem fase)")
	if bool(result["fallback_used"]):
		return _fail("accepts (caiu no fallback: %s)" % str(result["log"]))
	if def.solution == null:
		return _fail("accepts (sem solution anexada)")
	if def.solution.total_shots > def.ammo:
		return _fail("accepts (solução exige mais tiros que a munição)")
	print("  [accepts] candidates=%s sims=%s ms=%s shots=%d" % [
		str(result["candidates"]), str(result["sims"]), str(result["ms"]), def.solution.total_shots])
	return 0


# Exigindo ricochete onde não há metal: tudo rejeitado => fallback final.
func _case_ricochet_fallback() -> int:
	var cfg := _test_cfg()
	cfg.required_ricochets_min = 1
	var result := await ProceduralLevelGenerator.generate(7, 2, root, 5, cfg)
	var def: LevelDefinition = result["def"]
	if def == null:
		return _fail("fallback (sem fase)")
	if not bool(result["fallback_used"]) or not bool(result["ultimate"]):
		return _fail("fallback (deveria usar o ultimate)")
	if not def.obstacles.is_empty():
		return _fail("fallback (ultimate deveria vir sem obstáculos)")
	if def.target == null or def.target.position != Vector2(1000, 326):
		return _fail("fallback (geometria do ultimate alterada)")
	return 0


# Seeds diferentes: pelo menos 2 layouts distintos em 6 seeds.
func _case_variety() -> int:
	var seen := {}
	for seed_value in [99, 100, 101, 102, 103, 104]:
		var result := await ProceduralLevelGenerator.generate(seed_value, 2, root, 10, _test_cfg())
		seen[JSON.stringify((result["def"] as LevelDefinition).to_dict())] = true
	if seen.size() < 2:
		return _fail("variety (6 seeds geraram a mesma fase)")
	print("  [variety] %d layouts distintos em 6 seeds" % seen.size())
	return 0


func _fail(message: String) -> int:
	printerr("  [generator] " + message)
	return 1
