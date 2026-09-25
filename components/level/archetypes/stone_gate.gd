class_name LevelArchetypeStoneGate extends LevelArchetype
## Portão de pedra: 1+ pedras sobre a rota (2 hits para destruir) +
## vidros fora da rota. Pede ao menos 2 tiros (filtro por min_ammo).

func id() -> StringName:
	return &"stone_gate"


func min_ammo() -> int:
	return 2


func place(def: LevelDefinition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> bool:
	if cfg.stone_count.y < 1:
		return false
	set_target(def, spot_target(rng))
	var stones := maxi(count_in(rng, cfg.stone_count), 1)
	if not place_on_lane(def, rng, ObstacleDefinition.KIND_STONE, BLOCK_SCALE, stones):
		return false
	return place_off_lane(def, rng, ObstacleDefinition.KIND_GLASS, GLASS_SCALE, count_in(rng, cfg.glass_count))
