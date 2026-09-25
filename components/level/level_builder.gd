class_name LevelBuilder extends Node
## Transforma LevelDefinition em Nodes jogáveis (Etapa 7, docs/plan.md §12).
## Só instancia o que os dados mandam; não escolhe posições, não valida,
## não resolve. Limpa o grupo "level_spawned" antes (queue_free + 1
## physics_frame para tirar os corpos antigos do espaço físico).
## Cenas dos obstáculos via MaterialRules.scene_for (fonte única com o
## SimulationWorld). Shards usam os fallbacks das cenas (padrão 5).

const TARGET_SCENE := preload("res://components/target/target.tscn")


## Monta a fase em `world` (contêiner em (0,0): posição local == global).
## Retorna {"target": Target ou null, "obstacles": Array[Node2D]}.
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
	var target: Target = null
	if def.target != null:
		target = TARGET_SCENE.instantiate() as Target
		target.position = def.target.position
		target.add_to_group("level_spawned")
		world.add_child(target)
	return {"target": target, "obstacles": obstacles}


func clear(world: Node2D) -> void:
	for child in world.get_children():
		if child.is_in_group("level_spawned"):
			world.remove_child(child)
			child.queue_free()
