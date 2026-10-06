class_name FastLevelGenerator extends RefCounted
## Porta de entrada da fase real (Game).
##
## A lógica anterior (composition-first + solver analítico) foi
## completamente descartada e substituída pelo gerador em grade
## discreta ([GridLevelGenerator]): intenção -> dimensões -> Floor ->
## Cannon -> Target -> desafio -> Structures -> validação ->
## LevelDefinition. Sem física, sem Nodes, sem RNG global: mesma
## (seed, versão, fase) => mesma LevelDefinition.
##
## Mantém a API ({def, candidates, sims, ms, score, fallback_used,
## ultimate, log}) para não tocar no fluxo do jogo (`screens/game.gd`).

const MAX_ATTEMPTS := 30
const TIME_BUDGET_MS := 250


static func generate(seed_value: int, level_number: int, cfg_override: DifficultyConfig = null) -> Dictionary:
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
