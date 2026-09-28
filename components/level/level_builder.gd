class_name LevelBuilder extends Node
## Transforma LevelDefinition em Nodes jogáveis (docs/plan.md, Etapa 7).
## Só CONCRETIZA a composição aprovada: instancia floors, structures,
## obstáculos e alvo rotacionado exatamente como os dados mandam. Não
## escolhe posições, não valida, não resolve. Limpa o grupo
## "level_spawned" antes (queue_free + 1 physics_frame para tirar os
## corpos antigos do espaço físico).
## Cenas dos obstáculos via MaterialRules.scene_for (fonte única com o
## SimulationWorld). Shards usam os fallbacks das cenas (padrão 5).
## A pose do canhão volta no resultado ("cannon_position",
## "cannon_scale") para `game.gd` aplicar — o canhão continua nó da
## cena, só posicionado/escalado pela composição.

const TARGET_SCENE := preload("res://components/target/target.tscn")
const FLOOR_SCENE := preload("res://components/floor/floor.tscn")
const STRUCTURE_SCENE := preload("res://components/structure/Structure.tscn")

const GROUND_Y := 670.0
const GROUND_FROM_X := 50.0
const GROUND_TO_X := 1250.0
const GROUND_SCALE := Vector2(0.2, 0.2)


## Monta a fase em `world` (contêiner em (0,0): posição local == global).
## Retorna {"target", "obstacles": Array, "floors": Array,
## "structures": Array, "cannon_position": Vector2, "cannon_scale": ...}.
func build(world: Node2D, def: LevelDefinition) -> Dictionary:
	clear(world)
	await world.get_tree().physics_frame
	var obstacles: Array = []
	for obstacle in def.obstacles:
		if not MaterialRules.is_known(obstacle.kind):
			push_warning("LevelBuilder: kind '%s' ignorado." % String(obstacle.kind))
			continue
		var node := MaterialRules.scene_for(obstacle.kind).instantiate() as Node2D
		node.position = obstacle.position
		node.rotation_degrees = obstacle.rotation_degrees
		node.scale = obstacle.scale
		node.add_to_group("level_spawned")
		world.add_child(node)
		obstacles.append(node)
	var structures: Array = []
	for structure in def.structures:
		var beam := STRUCTURE_SCENE.instantiate() as Node2D
		beam.position = structure.position
		beam.rotation_degrees = structure.rotation_degrees
		beam.scale = structure.scale
		beam.add_to_group("level_spawned")
		world.add_child(beam)
		structures.append(beam)
	var target: Target = null
	if def.target != null:
		target = TARGET_SCENE.instantiate() as Target
		target.position = def.target.position
		# Rotação funcional da composição (Etapa 7).
		target.rotation_degrees = def.target.rotation_degrees
		target.add_to_group("level_spawned")
		world.add_child(target)
	var floors := build_floor(world, def)
	return {"target": target, "obstacles": obstacles, "floors": floors,
		"structures": structures, "cannon_position": def.cannon_position,
		"cannon_scale": def.cannon_scale}


func clear(world: Node2D) -> void:
	for child in world.get_children():
		if child.is_in_group("level_spawned"):
			world.remove_child(child)
			child.queue_free()


## Piso da composição: cada FloorDefinition vira um tile. Sem floors na
## def (fase legada v1 / fallback ultimate), mantém a faixa plana legada.
func build_floor(world: Node2D, def: LevelDefinition) -> Array:
	if def.floors.is_empty():
		return build_ground(world)
	var floors: Array = []
	for floor in def.floors:
		var tile := FLOOR_SCENE.instantiate() as Node2D
		tile.position = floor.position
		tile.scale = floor.scale
		tile.add_to_group("level_spawned")
		world.add_child(tile)
		floors.append(tile)
	return floors


func build_ground(world: Node2D) -> Array:
	var floors: Array = []
	var x := GROUND_FROM_X
	while x <= GROUND_TO_X:
		var floor := FLOOR_SCENE.instantiate() as Node2D
		floor.position = Vector2(x, GROUND_Y)
		floor.scale = GROUND_SCALE
		floor.add_to_group("level_spawned")
		world.add_child(floor)
		floors.append(floor)
		x += 100.0
	return floors
