class_name DifficultyConfig extends Resource
## Parâmetros de dificuldade de uma fase (Etapa 1, docs/plan.md §4.4).
## Preenchida por `DifficultyTable.get_config()`; consumida pelo gerador
## (Etapa 6) e pelo validador (Etapa 3). A banda [score_min, score_max]
## usa a métrica do §8 do plano; valores iniciais a calibrar na Etapa 8.

@export var level_number: int = 1
@export var ammo: int = 3 # 1..4 (RN-03 do PRD)
@export var max_obstacles: int = 3
@export var glass_count: Vector2i = Vector2i(0, 2) # (min, max)
@export var stone_count: Vector2i = Vector2i(0, 0)
@export var metal_count: Vector2i = Vector2i(0, 0)
@export var required_ricochets_min: int = 0 # 0 (fase ≤10) ou 1..2 (fase 11+)
@export var allowed_archetypes: Array[StringName] = [&"open_shot"]
@export var solver_angle_step: float = 2.0 # graus; Etapa 5 calibra
@export var solver_power_step: float = 0.1
@export var score_min: float = 0.0
@export var score_max: float = 8.0


func to_dict() -> Dictionary:
	var archetypes: Array = []
	for archetype in allowed_archetypes:
		archetypes.append(String(archetype))
	return {
		"level_number": level_number,
		"ammo": ammo,
		"max_obstacles": max_obstacles,
		"glass_count": {"x": glass_count.x, "y": glass_count.y},
		"stone_count": {"x": stone_count.x, "y": stone_count.y},
		"metal_count": {"x": metal_count.x, "y": metal_count.y},
		"required_ricochets_min": required_ricochets_min,
		"allowed_archetypes": archetypes,
		"solver_angle_step": solver_angle_step,
		"solver_power_step": solver_power_step,
		"score_min": score_min,
		"score_max": score_max,
	}


static func from_dict(data: Dictionary) -> DifficultyConfig:
	var cfg := DifficultyConfig.new()
	cfg.level_number = int(data.get("level_number", 1))
	cfg.ammo = int(data.get("ammo", 3))
	cfg.max_obstacles = int(data.get("max_obstacles", 3))
	var glass: Dictionary = data.get("glass_count", {"x": 0, "y": 2})
	cfg.glass_count = Vector2i(int(glass.get("x", 0)), int(glass.get("y", 2)))
	var stone: Dictionary = data.get("stone_count", {"x": 0, "y": 0})
	cfg.stone_count = Vector2i(int(stone.get("x", 0)), int(stone.get("y", 0)))
	var metal: Dictionary = data.get("metal_count", {"x": 0, "y": 0})
	cfg.metal_count = Vector2i(int(metal.get("x", 0)), int(metal.get("y", 0)))
	cfg.required_ricochets_min = int(data.get("required_ricochets_min", 0))
	cfg.allowed_archetypes.clear()
	for archetype in Array(data.get("allowed_archetypes", [&"open_shot"])):
		cfg.allowed_archetypes.append(StringName(str(archetype)))
	cfg.solver_angle_step = float(data.get("solver_angle_step", 2.0))
	cfg.solver_power_step = float(data.get("solver_power_step", 0.1))
	cfg.score_min = float(data.get("score_min", 0.0))
	cfg.score_max = float(data.get("score_max", 8.0))
	return cfg
