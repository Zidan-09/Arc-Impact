class_name LevelArchetypeBunker extends LevelArchetype
## Bunker: alvo semi-cercado por 3 metais (cima/baixo/direita, a 210px
## para não violar a exclusão de 100px do validador), boca aberta para
## o lado do canhão + vidros fora da rota. Precisa de 3 metais na cota.

func id() -> StringName:
	return &"bunker"


func place(def: LevelDefinition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> bool:
	if cfg.metal_count.y < 3:
		return false
	var before := def.obstacles.size()
	# Alvo com sala ao redor: longe das bordas para caber o cerco.
	var center := Vector2(rng.randf_range(950.0, 1050.0), rng.randf_range(250.0, 470.0))
	set_target(def, center)
	var spots := [center + Vector2(0, -210), center + Vector2(0, 210), center + Vector2(210, 0)]
	for i in spots.size():
		if not fits(def, ObstacleDefinition.KIND_METAL, spots[i], BLOCK_SCALE):
			rollback(def, before)
			return false
		var ob := add_ob(def, ObstacleDefinition.KIND_METAL, spots[i], BLOCK_SCALE)
		ob.id = "wall_%d" % (i + 1)
	return place_off_lane(def, rng, ObstacleDefinition.KIND_GLASS, GLASS_SCALE, count_in(rng, cfg.glass_count))
