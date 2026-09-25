class_name ProceduralLevelGenerator extends RefCounted
## Gera candidatos e devolve o primeiro aprovado em
## validador -> solver -> ricochetes -> banda de score (Etapas 6+8+9,
## docs/plan.md §5/§8/§11). Único dono de um RandomNumberGenerator com
## seed explícita: mesma (seed, versão, fase) => mesma sequência de
## candidatos => mesma fase. Não instancia Nodes da fase (só os mundos
## temporários do solver); não usa RNG global. Esgotados os candidatos
## (ou estourado TIME_BUDGET_MS), tenta FALLBACK_SEEDS da banda e por
## fim o ultimate aberto (geometria do smoke test: alvo em 1000,326 sem
## obstáculos, solução ângulo 10 / força 1.0 comprovada pelo teste).

const MAX_CANDIDATES := 40
const TIME_BUDGET_MS := 300

## Seeds pré-validadas por banda (Etapa 9): o ultimate aberto resolve
## qualquer banda fácil; bandas com metal usam seeds que o gerador já
## aprovou uma vez (curadoria via benchmark; lista cresce com medidas).
## Chave = "from-to" da banda; valor = seeds candidatas nessa ordem.
const FALLBACK_SEEDS := {
	"1-3": [7, 99, 42],
	"4-6": [7, 99, 42],
	"7-10": [7, 99, 42],
	"11-15": [11, 7, 99],
	"16-20": [16, 11, 7],
}


## Retorna {"def": LevelDefinition, "candidates": int, "sims": int,
##          "ms": int, "score": float, "fallback_used": bool,
##          "ultimate": bool, "log": Array[String]}.
## `cfg_override` é gancho de teste.
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
		# Orçamento de wall-clock só em produção: testes (cfg_override)
		# usam física real-time e estourariam 300ms por construção.
		if cfg_override == null and Time.get_ticks_msec() - start > TIME_BUDGET_MS:
			log.append("budget")
			break
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
		var cfg_check := LevelValidator.validate_config(def, cfg)
		if not bool(cfg_check["ok"]):
			log.append("config:" + str((cfg_check["errors"] as Array).front()))
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
		var score := DifficultyScorer.score(def, record)
		if not DifficultyScorer.in_band(score, cfg):
			log.append("score:%.2f" % score)
			continue
		def.solution = record
		return _report(def, tried, total_sims, start, score, false, false, log)
	# Rede 1: seeds curadas da banda (mesmo pipeline, rng próprio).
	var rescued := await _try_fallback_seeds(seed_value, level_number, cfg, parent, log)
	if rescued.has("def"):
		total_sims += int(rescued["sims"])
		tried += int(rescued["candidates"])
		return _report(rescued["def"], tried, total_sims, start, float(rescued["score"]), true, false, log)
	var ultimate := ultimate_fallback(seed_value, level_number, cfg)
	return _report(ultimate, tried, total_sims, start, -1.0, true, true, log)


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


## Tenta as seeds curadas da banda antes do ultimate. Cada seed roda o
## pipeline completo (arquétipo sorteado pelo hash da seed, validador,
## solver, banda) com orçamento próprio de 3 candidatos.
static func _try_fallback_seeds(seed_value: int, level_number: int, cfg: DifficultyConfig, parent: Node, log: Array[String]) -> Dictionary:
	var key := _band_key(level_number)
	var seeds: Array = FALLBACK_SEEDS.get(key, [])
	for fb_seed in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:%d:%d" % [int(fb_seed), LevelDefinition.GENERATOR_VERSION, level_number])
		for _i in 3:
			var arch := pick_archetype(rng, cfg)
			if arch == null:
				break
			var def := skeleton(seed_value, level_number, cfg)
			if not arch.place(def, rng, cfg):
				continue
			if not bool(LevelValidator.validate(def)["ok"]):
				continue
			if not bool(LevelValidator.validate_config(def, cfg)["ok"]):
				continue
			var sims := [0]
			var record := await LevelSolver.solve(def, cfg, parent, LevelSolver.EARLY_EXIT_DEFAULT, sims)
			if record == null:
				continue
			if record.total_ricochets < cfg.required_ricochets_min:
				continue
			var score := DifficultyScorer.score(def, record)
			if not DifficultyScorer.in_band(score, cfg):
				continue
			def.solution = record
			log.append("fallback-seed:%d" % int(fb_seed))
			return {"def": def, "sims": sims[0], "candidates": 1, "score": score}
	return {}


static func _band_key(level_number: int) -> String:
	for band in DifficultyTable._bands():
		if level_number >= int(band["from"]) and level_number <= int(band["to"]):
			return "%d-%d" % [int(band["from"]), int(band["to"])]
	var hardest: Dictionary = DifficultyTable._bands()[DifficultyTable._bands().size() - 1]
	return "%d-%d" % [int(hardest["from"]), int(hardest["to"])]


## Rede final: sem obstáculos, alvo na geometria comprovada pelo smoke
## test (caso open_direct_hit). Sem solution anexada: o smoke test é a
## prova de solubilidade; o jogo segue jogável mesmo com divergência.
static func ultimate_fallback(seed_value: int, level_number: int, cfg: DifficultyConfig) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = cfg.ammo
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1000, 326)
	return def


static func _report(def: LevelDefinition, tried: int, sims: int, start: int, score: float, fallback_used: bool, ultimate: bool, log: Array[String]) -> Dictionary:
	return {
		"def": def,
		"candidates": tried,
		"sims": sims,
		"ms": Time.get_ticks_msec() - start,
		"score": score,
		"fallback_used": fallback_used,
		"ultimate": ultimate,
		"log": log,
	}
