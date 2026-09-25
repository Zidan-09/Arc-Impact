class_name LevelArchetypeComboOrder extends LevelArchetype
## Ordem importa: vidro na frente (t ~0.35) e pedra atrás (t ~0.6) sobre
## a rota. Gastar o tiro na pedra antes de limpar o vidro cobra caro.
## Pede ao menos 2 tiros (filtro por min_ammo).

func id() -> StringName:
	return &"combo_order"


func min_ammo() -> int:
	return 2


func place(def: LevelDefinition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> bool:
	if cfg.glass_count.y < 1 or cfg.stone_count.y < 1:
		return false
	set_target(def, spot_target(rng))
	var glass := maxi(count_in(rng, cfg.glass_count), 1)
	if not place_on_lane(def, rng, ObstacleDefinition.KIND_GLASS, GLASS_SCALE, glass, 0.3, 0.45):
		return false
	var stone := maxi(count_in(rng, cfg.stone_count), 1)
	return place_on_lane(def, rng, ObstacleDefinition.KIND_STONE, BLOCK_SCALE, stone, 0.55, 0.7)
