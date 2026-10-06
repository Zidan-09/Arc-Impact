class_name ProceduralLevelGenerator extends RefCounted
## Compatibilidade: a lógica anterior (arquétipos-places + LevelSolver
## com física) foi completamente descartada. Toda a geração passa pelo
## [GridLevelGenerator]; este nome segue existindo apenas como apelido
## para chamadores legados (ex. fluxo de guides).

const MAX_CANDIDATES := 30
const TIME_BUDGET_MS := 300


static func generate(seed_value: int, level_number: int, _parent: Node = null, max_candidates: int = MAX_CANDIDATES, cfg_override: DifficultyConfig = null) -> Dictionary:
	var start := Time.get_ticks_msec()
	var result := GridLevelGenerator.generate(seed_value, level_number, cfg_override)
	var def: LevelDefinition = result["def"]
	return {
		"def": def,
		"grid_ascii": String(result["grid_ascii"]),
		"archetype": String(result["archetype"]),
		"candidates": int(result["candidates"]),
		"sims": 0,
		"ms": Time.get_ticks_msec() - start,
		"score": float(result["score"]),
		"fallback_used": bool(result["fallback_used"]),
		"ultimate": bool(result["ultimate"]),
		"log": result["log"],
	}
