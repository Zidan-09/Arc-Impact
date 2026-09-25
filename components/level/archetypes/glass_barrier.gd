class_name LevelArchetypeGlassBarrier extends LevelArchetype
## Barreira de vidro: 1+ vidros SOBRE a rota (atravessáveis com *= 0.85,
## ensinam a atenuação) + o restante da cota fora da rota.

func id() -> StringName:
	return &"glass_barrier"


func place(def: LevelDefinition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> bool:
	set_target(def, spot_target(rng))
	var total := count_in(rng, cfg.glass_count)
	var on_lane := maxi(total, 1) # motivo exige ao menos 1 na rota
	if not place_on_lane(def, rng, ObstacleDefinition.KIND_GLASS, GLASS_SCALE, on_lane):
		return false
	return place_off_lane(def, rng, ObstacleDefinition.KIND_GLASS, GLASS_SCALE, maxi(total - on_lane, 0))
