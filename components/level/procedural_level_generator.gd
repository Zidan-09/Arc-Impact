class_name ProceduralLevelGenerator extends RefCounted
## Gera candidatos e devolve o primeiro aprovado em
## validador -> solver -> ricochetes mínimos (Etapa 6, docs/plan.md §5).
## Único dono de um RandomNumberGenerator com seed explícita: mesma
## (seed, versão, fase) => mesma sequência de candidatos => mesma fase.
## Não instancia Nodes da fase (só os mundos temporários do solver);
## não usa RNG global. Banda de score (§8) fica para a Etapa 8: aqui
## valem munição da config, integridade estrutural, solução real e
## ricochetes mínimos (RN-06). Esgotados os candidatos, cai no fallback
## final: fase aberta com geometria do smoke test (alvo em 1000,326 sem
## obstáculos, solução ângulo 10 / força 1.0 comprovada pelo teste) —
## em vez de lista de seeds, que só a Etapa 9 pode curar com medidas.

const MAX_CANDIDATES := 40


## Retorna {"def": LevelDefinition, "candidates": int, "sims": int,
##          "ms": int, "fallback_used": bool, "ultimate": bool,
##          "log": Array[String]}. `cfg_override` é gancho de teste.
static func generate(seed_value: int, level_number: int, parent: Node, max_candidates: int = MAX_CANDIDATES, cfg_override: DifficultyConfig = null) -> Dictionary:
	# Tipo explícito: o ramo null do ternário impede a inferência do `:=`.
	var cfg: DifficultyConfig = cfg_override if cfg_override != null else DifficultyTable.get_config(level_number)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d" % [seed_value, LevelDefinition.GENERATOR_VERSION, level_number])
	var total_sims := 0
	var log: Array[String] = []
	var start := Time.get_ticks_msec()
	var tried := 0
	for _attempt in maxi(max_candidates, 1):
		tried += 1
		var arch := pick_archetype(rng, cfg)
		if arch == null:
			log.append("no-archetype")
			break
		var def := skeleton(seed_value, level_number, cfg)
		if not arch.place(def, rng, cfg):
			log.append("placement:" + String(arch.id()))
			continue
		var validation := LevelValidator.validate(def)
		if not bool(validation["ok"]):
			log.append("validate:" + str((validation["errors"] as Array).front()))
			continue
		var sims := [0]
		var record := await LevelSolver.solve(def, cfg, parent, LevelSolver.EARLY_EXIT_DEFAULT, sims)
		total_sims += sims[0]
		if record == null:
			log.append("unsolved:" + String(arch.id()))
			continue
		if record.total_ricochets < cfg.required_ricochets_min:
			log.append("ricochet:" + String(arch.id()))
			continue
		def.solution = record
		return _report(def, tried, total_sims, start, false, false, log)
	var ultimate := ultimate_fallback(seed_value, level_number, cfg)
	return _report(ultimate, tried, total_sims, start, true, true, log)


static func pick_archetype(rng: RandomNumberGenerator, cfg: DifficultyConfig) -> LevelArchetype:
	var options: Array[LevelArchetype] = []
	for archetype_id in cfg.allowed_archetypes:
		var arch := make_archetype(archetype_id)
		if arch != null and arch.min_ammo() <= cfg.ammo:
			options.append(arch)
	if options.is_empty():
		return null
	return options[rng.randi_range(0, options.size() - 1)]


static func make_archetype(archetype_id: StringName) -> LevelArchetype:
	match archetype_id:
		&"open_shot":
			return LevelArchetypeOpenShot.new()
		&"glass_barrier":
			return LevelArchetypeGlassBarrier.new()
		&"stone_gate":
			return LevelArchetypeStoneGate.new()
		&"blocked_direct":
			return LevelArchetypeBlockedDirect.new()
		&"bunker":
			return LevelArchetypeBunker.new()
		&"combo_order":
			return LevelArchetypeComboOrder.new()
	return null


static func skeleton(seed_value: int, level_number: int, cfg: DifficultyConfig) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = cfg.ammo
	return def


## Rede final: sem obstáculos, alvo na geometria comprovada pelo smoke
## test (caso open_direct_hit). Sem solution anexada (Etapa 8 decide se
## o fallback passa pelo solver; o smoke test é a prova de solubilidade).
static func ultimate_fallback(seed_value: int, level_number: int, cfg: DifficultyConfig) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = cfg.ammo
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1000, 326)
	return def


static func _report(def: LevelDefinition, tried: int, sims: int, start: int, fallback_used: bool, ultimate: bool, log: Array[String]) -> Dictionary:
	return {
		"def": def,
		"candidates": tried,
		"sims": sims,
		"ms": Time.get_ticks_msec() - start,
		"fallback_used": fallback_used,
		"ultimate": ultimate,
		"log": log,
	}
