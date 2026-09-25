class_name LevelSolver extends RefCounted
## Resposta a "existe sequência de tiros que atinge o alvo?"
## (docs/plan.md §7). Etapa 4: só TIRO ÚNICO via simulação física real
## (`simulate_shot`); a busca multi-tiro em BFS vem na Etapa 5.

const SIMULATION_SCENE := preload("res://components/level/simulation_world.tscn")


## Estado inicial da fase: pedra com HP cheio, vidro vivo.
## Formato: {"stone_hp": {id: hp}, "glass_alive": {id: bool}}.
static func initial_state(def: LevelDefinition) -> Dictionary:
	var stone_hp := {}
	var glass_alive := {}
	for obstacle in def.obstacles:
		if obstacle.kind == ObstacleDefinition.KIND_STONE:
			stone_hp[obstacle.id] = MaterialRules.max_hp(obstacle.kind)
		elif obstacle.kind == ObstacleDefinition.KIND_GLASS:
			glass_alive[obstacle.id] = true
	return {"stone_hp": stone_hp, "glass_alive": glass_alive}


## Simula um tiro numa cópia invisível da fase sob `parent` (ex.: root
## do teste ou um contêiner oculto do jogo) e libera tudo ao final.
## Retorna o dicionário de SimulationWorld.run_shot().
static func simulate_shot(def: LevelDefinition, state: Dictionary, angle: float, power: float, parent: Node) -> Dictionary:
	var world := SIMULATION_SCENE.instantiate() as SimulationWorld
	parent.add_child(world)
	var result := await world.run_shot(def, state, angle, power)
	world.queue_free()
	return result
