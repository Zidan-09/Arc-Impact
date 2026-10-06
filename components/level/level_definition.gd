class_name LevelDefinition extends Resource
## Representação completa de uma fase em dados puros e serializáveis
## (docs/plan.md, Etapa 1). Tudo que o LevelBuilder precisa para
## reconstruir a fase; mesma seed + mesma versão do gerador => mesmo
## dicionário. Não instancia Nodes, não usa RNG.
##
## v2 (composition-first): a fase carrega `floors` + `structures` como
## dados, a pose do canhão (`cannon_position` + `cannon_scale`, altura
## variável decidida pela composição) e a linhagem compositiva
## (`composition_tags`, ex. ["platform", "gate"] — tags, nunca templates
## rígidos). Dicts v1 (sem as chaves novas) desserializam com padrões
## que reproduzem a fase legada (chão plano via builder, canhão 0.2).

const GENERATOR_VERSION: int = 3 # v3: grade discreta intencional (GridLevelGenerator)

@export var seed: int = 0
@export var generator_version: int = GENERATOR_VERSION
@export var level_number: int = 1
@export var ammo: int = 3 # 1..4 (RN-03 do PRD)
@export var cannon_position: Vector2 = Vector2(173, 523)
@export var cannon_scale: Vector2 = Vector2(0.16, 0.16) # canônica (ver Cannon.CANNON_SCALE)
@export var cannon_angle_min: float = -20.0 # espelha cannon.gd
@export var cannon_angle_max: float = 83.0 # espelha cannon.gd
@export var power_min: float = 0.3 # espelha power_slider.gd
@export var power_max: float = 1.0
@export var base_shot_speed: float = 2000.0 # espelha cannon.gd
@export var play_bounds: Rect2 = Rect2(0, 0, 1280, 720) # viewport base
## Área visível total da fase para a câmera (docs/plan.md). Na v1/v2
## espelha `play_bounds`; o gerador futuro pode ampliá-la sem tocar nas
## regras (validador/solver/kill continuam lendo `play_bounds`).
@export var world_bounds: Rect2 = Rect2(0, 0, 1280, 720)
@export var target: TargetDefinition
@export var obstacles: Array[ObstacleDefinition] = []
@export var floors: Array[FloorDefinition] = []
@export var structures: Array[StructureDefinition] = []
@export var composition_tags: Array[StringName] = []

## Preenchido pelo solver (Etapa 5); nulo até lá. Mantido fora do
## @export porque SolutionRecord é RefCounted, não Resource.
var solution: SolutionRecord = null


func to_dict() -> Dictionary:
	var obstacle_dicts: Array = []
	for obstacle in obstacles:
		obstacle_dicts.append(obstacle.to_dict())
	var floor_dicts: Array = []
	for floor in floors:
		floor_dicts.append(floor.to_dict())
	var structure_dicts: Array = []
	for structure in structures:
		structure_dicts.append(structure.to_dict())
	var tag_strings: Array = []
	for tag in composition_tags:
		tag_strings.append(String(tag))
	return {
		"seed": seed,
		"generator_version": generator_version,
		"level_number": level_number,
		"ammo": ammo,
		"cannon_position": {"x": cannon_position.x, "y": cannon_position.y},
		"cannon_scale": {"x": cannon_scale.x, "y": cannon_scale.y},
		"cannon_angle_min": cannon_angle_min,
		"cannon_angle_max": cannon_angle_max,
		"power_min": power_min,
		"power_max": power_max,
		"base_shot_speed": base_shot_speed,
		"play_bounds": {
			"x": play_bounds.position.x, "y": play_bounds.position.y,
			"w": play_bounds.size.x, "h": play_bounds.size.y,
		},
		"world_bounds": {
			"x": world_bounds.position.x, "y": world_bounds.position.y,
			"w": world_bounds.size.x, "h": world_bounds.size.y,
		},
		"target": target.to_dict() if target != null else {},
		"obstacles": obstacle_dicts,
		"floors": floor_dicts,
		"structures": structure_dicts,
		"composition_tags": tag_strings,
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
	# Compatibilidade: dicts v1 não têm escala do canhão (sempre 0.2).
	var cannon_scl: Dictionary = data.get("cannon_scale", {"x": 0.16, "y": 0.16})
	def.cannon_scale = Vector2(float(cannon_scl.get("x", 0.16)), float(cannon_scl.get("y", 0.16)))
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
	# Compatibilidade: dicts serializados antes de `world_bounds` caem no
	# `play_bounds` (na v1 os dois coincidem por construção).
	var wbounds: Dictionary = data.get("world_bounds", {
		"x": def.play_bounds.position.x, "y": def.play_bounds.position.y,
		"w": def.play_bounds.size.x, "h": def.play_bounds.size.y,
	})
	def.world_bounds = Rect2(
		float(wbounds.get("x", 0.0)), float(wbounds.get("y", 0.0)),
		float(wbounds.get("w", 1280.0)), float(wbounds.get("h", 720.0))
	)
	var target_data: Dictionary = data.get("target", {})
	def.target = TargetDefinition.from_dict(target_data) if not target_data.is_empty() else null
	def.obstacles.clear()
	for obstacle_data in Array(data.get("obstacles", [])):
		def.obstacles.append(ObstacleDefinition.from_dict(obstacle_data))
	# Compatibilidade: dicts v1 não têm floors/structures/tags (fase plana
	# legada: o builder usa a faixa padrão quando `floors` está vazio).
	def.floors.clear()
	for floor_data in Array(data.get("floors", [])):
		def.floors.append(FloorDefinition.from_dict(floor_data))
	def.structures.clear()
	for structure_data in Array(data.get("structures", [])):
		def.structures.append(StructureDefinition.from_dict(structure_data))
	def.composition_tags.clear()
	for tag in Array(data.get("composition_tags", [])):
		def.composition_tags.append(StringName(str(tag)))
	var solution_data: Dictionary = data.get("solution", {})
	def.solution = SolutionRecord.from_dict(solution_data) if not solution_data.is_empty() else null
	return def
