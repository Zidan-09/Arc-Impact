class_name LevelSolver extends RefCounted
## Resposta a "existe sequência de tiros que atinge o alvo?"
## (docs/plan.md §7). Etapa 5: BFS sobre tiros discretizados, cada
## transição simulada na física real (`simulate_shot`). Profundidade
## limitada por `def.ammo` (1..4); estados repetidos podados por hash;
## early-exit após `max_solutions` acertos; teto de simulações como
## guarda-orçamento (Etapa 9 calibra os números contra os 300 ms).
## Por que BFS e não A*/gea analítica: o espaço de ação é contínuo, a
## transição custa uma simulação e não há heurística admissível com
## rebotes/destruição — ver §7.2 do plano (alternativas rejeitadas).

const SIMULATION_SCENE := preload("res://components/level/simulation_world.tscn")

const EARLY_EXIT_DEFAULT := 3
const MAX_SIMULATIONS := 800
const FRONTIER_CAP := 24
const MARGIN_PROBE_DEGREES := 0.5


## Estado inicial da fase: pedra com HP cheio, vidro vivo.
## Formato: {"stone_hp": {id: hp}, "glass_alive": {id: bool}}.
static func initial_state(def: LevelDefinition) -> Dictionary:
	var stone_hp := {}
	var glass_alive := {}
	for obstacle in def.obstacles:
		if obstacle.kind == ObstacleDefinition.KIND_STONE:
			stone_hp[obstacle.id] = MaterialRules.max_hp(obstacle.kind)
		elif obstacle.kind == ObstacleDefinition.KIND_GLASS:
			glass_alive[obstacle.id] = true
	return {"stone_hp": stone_hp, "glass_alive": glass_alive}


## Procura sequência de ≤ def.ammo tiros que atinge o alvo.
## Retorna SolutionRecord (a mais rasa; desempate: menos ricochetes)
## ou null. `sims_run` sai com o nº de simulações executadas (métrica
## de custo p/ Etapa 9). `parent` recebe os mundos temporários.
static func solve(def: LevelDefinition, cfg: DifficultyConfig, parent: Node, max_solutions: int = EARLY_EXIT_DEFAULT, sims_run: Array = []) -> SolutionRecord:
	var angles := _grade_values(def.cannon_angle_min, def.cannon_angle_max, cfg.solver_angle_step)
	var powers := _grade_values(def.power_min, def.power_max, cfg.solver_power_step)
	var sims := 0
	var best: SolutionRecord = null
	var found := 0
	var visited := {}
	var frontier: Array = [{"state": initial_state(def), "seq": []}]

	for depth in range(1, def.ammo + 1):
		var next_frontier: Array = []
		for entry in frontier:
			for angle in angles:
				for power in powers:
					if sims >= MAX_SIMULATIONS:
						push_warning("LevelSolver.solve: teto de simulações (%d) atingido." % MAX_SIMULATIONS)
						return _finish(best, sims_run, sims)
					var result := await simulate_shot(def, entry["state"], angle, power, parent)
					sims += 1
					var shot := {"angle": angle, "power": power,
						"ricochets": int(result["ricochets"]),
						"destroyed": Array(result["destroyed"])}
					if bool(result["hit_target"]):
						found += 1
						var candidate := _make_record(entry["seq"] + [shot])
						if best == null or candidate.total_ricochets < best.total_ricochets:
							best = candidate
						if found >= max_solutions:
							best.solutions_found = found
							best.min_angle_margin = await _probe_margin(def, best.shots, parent)
							sims += 2 * best.total_shots
							return _finish(best, sims_run, sims)
					elif depth < def.ammo:
						var key := _state_key(result["end_state"])
						if not visited.has(key) and next_frontier.size() < FRONTIER_CAP:
							visited[key] = true
							next_frontier.append({"state": result["end_state"], "seq": entry["seq"] + [shot]})
		frontier = next_frontier
		if frontier.is_empty():
			break

	if best != null:
		best.solutions_found = found
		best.min_angle_margin = await _probe_margin(def, best.shots, parent)
		sims += 2 * best.total_shots
	return _finish(best, sims_run, sims)


## Simula um tiro numa cópia invisível da fase sob `parent` (ex.: root
## do teste ou um contêiner oculto do jogo) e libera tudo ao final.
## Retorna o dicionário de SimulationWorld.run_shot().
static func simulate_shot(def: LevelDefinition, state: Dictionary, angle: float, power: float, parent: Node) -> Dictionary:
	var world := SIMULATION_SCENE.instantiate() as SimulationWorld
	parent.add_child(world)
	var result := await world.run_shot(def, state, angle, power)
	world.queue_free()
	return result


static func _finish(best: SolutionRecord, sims_run: Array, sims: int) -> SolutionRecord:
	if not sims_run.is_empty():
		sims_run[0] = sims
	return best


static func _make_record(shots: Array) -> SolutionRecord:
	var record := SolutionRecord.new()
	record.shots.clear()
	for shot in shots:
		record.shots.append(shot)
	record.total_shots = shots.size()
	var ricochets := 0
	for shot in shots:
		ricochets += int(shot["ricochets"])
	record.total_ricochets = ricochets
	record.solutions_found = 1
	return record


## Margem de precisão (graus, aproximação v1): repete a sequência
## vencedora com o 1º tiro perturbado ±MARGIN_PROBE_DEGREES. Ambos
## acertam => 0.5; um só => 0.25; nenhum => 0.0 (solução estreita).
## A Etapa 8 refina a métrica com a calibragem de dificuldade.
static func _probe_margin(def: LevelDefinition, shots: Array, parent: Node) -> float:
	var plus := await _replay_perturbed(def, shots, parent, MARGIN_PROBE_DEGREES)
	var minus := await _replay_perturbed(def, shots, parent, -MARGIN_PROBE_DEGREES)
	if plus and minus:
		return MARGIN_PROBE_DEGREES
	if plus or minus:
		return MARGIN_PROBE_DEGREES * 0.5
	return 0.0


static func _replay_perturbed(def: LevelDefinition, shots: Array, parent: Node, delta: float) -> bool:
	var state := initial_state(def)
	for i in shots.size():
		var angle: float = shots[i]["angle"]
		if i == 0:
			angle = clampf(angle + delta, def.cannon_angle_min, def.cannon_angle_max)
		var result := await simulate_shot(def, state, angle, float(shots[i]["power"]), parent)
		if bool(result["hit_target"]):
			return true
		state = result["end_state"]
	return false


static func _grade_values(min_value: float, max_value: float, step: float) -> Array[float]:
	var values: Array[float] = []
	var count := int(round((max_value - min_value) / step))
	for i in range(count + 1):
		values.append(minf(min_value + float(i) * step, max_value))
	return values


static func _state_key(state: Dictionary) -> String:
	var parts: Array[String] = []
	var hp: Dictionary = state.get("stone_hp", {})
	var ids := hp.keys()
	ids.sort()
	for id in ids:
		parts.append("%s:%d" % [str(id), int(hp[id])])
	var alive: Dictionary = state.get("glass_alive", {})
	var gids := alive.keys()
	gids.sort()
	for id in gids:
		parts.append("%s:%s" % [str(id), "1" if bool(alive[id]) else "0"])
	return "|".join(parts)
