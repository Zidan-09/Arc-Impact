class_name LevelDefinition extends Resource
## Representação completa de uma fase em dados puros e serializáveis
## (Etapa 1, docs/plan.md §4.1). Tudo que o LevelBuilder (Etapa 7)
## precisa para reconstruir a fase; mesma seed + mesma versão do
## gerador => mesmo dicionário. Não instancia Nodes, não usa RNG.

const GENERATOR_VERSION: int = 1 # bump quando o algoritmo mudar (Etapa 6+)

@export var seed: int = 0
@export var generator_version: int = GENERATOR_VERSION
@export var level_number: int = 1
@export var ammo: int = 3 # 1..4 (RN-03 do PRD)
@export var cannon_position: Vector2 = Vector2(173, 523) # fixo na v1
@export var cannon_angle_min: float = -20.0 # espelha cannon.gd
@export var cannon_angle_max: float = 83.0 # espelha cannon.gd
@export var power_min: float = 0.3 # espelha power_slider.gd
@export var power_max: float = 1.0
@export var base_shot_speed: float = 2000.0 # espelha cannon.gd
@export var play_bounds: Rect2 = Rect2(0, 0, 1280, 720) # viewport base
@export var target: TargetDefinition
@export var obstacles: Array[ObstacleDefinition] = []

## Preenchido pelo solver (Etapa 5); nulo até lá. Mantido fora do
## @export porque SolutionRecord é RefCounted, não Resource.
var solution: SolutionRecord = null


func to_dict() -> Dictionary:
	var obstacle_dicts: Array = []
	for obstacle in obstacles:
		obstacle_dicts.append(obstacle.to_dict())
	return {
		"seed": seed,
		"generator_version": generator_version,
		"level_number": level_number,
		"ammo": ammo,
		"cannon_position": {"x": cannon_position.x, "y": cannon_position.y},
		"cannon_angle_min": cannon_angle_min,
		"cannon_angle_max": cannon_angle_max,
		"power_min": power_min,
		"power_max": power_max,
		"base_shot_speed": base_shot_speed,
		"play_bounds": {
			"x": play_bounds.position.x, "y": play_bounds.position.y,
			"w": play_bounds.size.x, "h": play_bounds.size.y,
		},
		"target": target.to_dict() if target != null else {},
		"obstacles": obstacle_dicts,
		"solution": solution.to_dict() if solution != null else {},
	}


static func from_dict(data: Dictionary) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = int(data.get("seed", 0))
	def.generator_version = int(data.get("generator_version", GENERATOR_VERSION))
	def.level_number = int(data.get("level_number", 1))
	def.ammo = int(data.get("ammo", 3))
	var cannon_pos: Dictionary = data.get("cannon_position", {"x": 173.0, "y": 523.0})
	def.cannon_position = Vector2(float(cannon_pos.get("x", 173.0)), float(cannon_pos.get("y", 523.0)))
	def.cannon_angle_min = float(data.get("cannon_angle_min", -20.0))
	def.cannon_angle_max = float(data.get("cannon_angle_max", 83.0))
	def.power_min = float(data.get("power_min", 0.3))
	def.power_max = float(data.get("power_max", 1.0))
	def.base_shot_speed = float(data.get("base_shot_speed", 2000.0))
	var bounds: Dictionary = data.get("play_bounds", {"x": 0.0, "y": 0.0, "w": 1280.0, "h": 720.0})
	def.play_bounds = Rect2(
		float(bounds.get("x", 0.0)), float(bounds.get("y", 0.0)),
		float(bounds.get("w", 1280.0)), float(bounds.get("h", 720.0))
	)
	var target_data: Dictionary = data.get("target", {})
	def.target = TargetDefinition.from_dict(target_data) if not target_data.is_empty() else null
	def.obstacles.clear()
	for obstacle_data in Array(data.get("obstacles", [])):
		def.obstacles.append(ObstacleDefinition.from_dict(obstacle_data))
	var solution_data: Dictionary = data.get("solution", {})
	def.solution = SolutionRecord.from_dict(solution_data) if not solution_data.is_empty() else null
	return def
