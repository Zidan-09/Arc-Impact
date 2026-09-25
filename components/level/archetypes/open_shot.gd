class_name LevelArchetypeOpenShot extends LevelArchetype
## Tiro aberto: alvo à vista, 0-2 vidros fora da rota (fases 1-3).

func id() -> StringName:
	return &"open_shot"


func place(def: LevelDefinition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> bool:
	set_target(def, spot_target(rng))
	return place_off_lane(def, rng, ObstacleDefinition.KIND_GLASS, GLASS_SCALE, count_in(rng, cfg.glass_count))
