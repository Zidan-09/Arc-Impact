extends SceneTree
## Benchmark da Etapa 9 (DoD honesto: custo medido + extrapolação).
## Roda headless, sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/generation_benchmark.gd
## Usa grade grossa (10° x 0.35, ~16 sims/candidato) para caber em tempo
## de teste. A grade de produção (2.0° x 0.1, ~416 sims/candidato) é 26x
## maior — a extrapolação abaixo mostra por que os 300ms (RNF-004) não
## fecham com física em tempo real, e o que o código faz a respeito
## (orçamento + fallbacks + geração assíncrona no CannonController).
## Falha se o fallback não entregar fase válida; nunca falha por tempo.


func _initialize() -> void:
	Engine.time_scale = 1.0
	_run()


func _bench_cfg() -> DifficultyConfig:
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


func _run() -> void:
	await physics_frame
	var failures := 0
	var total_ms := 0
	var total_sims := 0
	var count := 0
	for seed_value in [7, 42, 99]:
		var start := Time.get_ticks_msec()
		var result := await ProceduralLevelGenerator.generate(seed_value, 2, root, 6, _bench_cfg())
		var wall := Time.get_ticks_msec() - start
		var def: LevelDefinition = result["def"]
		total_ms += wall
		total_sims += int(result["sims"])
		count += 1
		if not bool(LevelValidator.validate(def)["ok"]) or def.target == null:
			printerr("  [bench] fase inválida: seed=%d log=%s" % [seed_value, str(result["log"])])
			failures += 1
		print("  [bench] seed=%d ms=%d cands=%s sims=%s fallback=%s score=%.2f" % [
			seed_value, wall, str(result["candidates"]), str(result["sims"]),
			str(result["fallback_used"]), float(result.get("score", -1.0))])
	var per_sim := float(total_ms) / float(maxi(1, total_sims))
	# Medido em 2026-09-25 (desktop headless, física tempo real):
	# ~640ms/sim (7045ms / 11 sims). Grade produção tem ~416 sims por
	# profundidade vs ~16 na grossa (26x) => 1 candidato ≈ 4-5 min em
	# tempo real. Conclusão: RNF-004 (300ms) exige simulação acelerada
	# (step manual / física sem espera real) ou poda analítica antes do
	# solver — fora do escopo aqui. O que fecha: TIME_BUDGET_MS aborta,
	# FALLBACK_SEEDS + ultimate garantem fase jogável, e o
	# CannonController.load_level é assíncrono (sem travar o frame).
	print("  [bench] %d amostras, %d sims, %d ms total, ~%.0f ms/sim (tempo real)" % [count, total_sims, total_ms, per_sim])
	print("  [bench] extrapolação produção: 1 candidato ≈ %.0f sims × %.0f ms ≈ %.0f s (por isso o fallback existe)" % [416.0, per_sim, 416.0 * per_sim / 1000.0])
	if failures == 0:
		print("GENERATION_BENCHMARK: PASS")
	else:
		printerr("GENERATION_BENCHMARK: FAIL (%d checagens falharam)" % failures)
	Engine.time_scale = 1.0
	quit(failures)
