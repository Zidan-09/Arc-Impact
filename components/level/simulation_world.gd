class_name SimulationWorld extends Node2D
## Sandbox físico invisível para o LevelSolver (Etapa 4, docs/plan.md §7).
## Instancia as CENAS REAIS (mesmos shapes, materiais e scripts do jogo)
## com `shard_count = 0`: estilhaços são cosméticos, usam RNG global e
## poderiam colidir com o bullet — por isso ficam FORA da simulação
## (DoD: `shard_count == 0` no resultado prova a ausência).
## Nunca toca a cena visível: vive sob o parent que o chamador indicar.
## Términos contam physics_frames (determinístico, insensível a
## Engine.time_scale). Tweens dos obstáculos rodam, mas a lógica usa só
## HP/posição/velocidade — o tween é visual e não decide nada aqui.
## Aproximações documentadas: sem paredes do cano (o spawn no muzzle já
## as evita no jogo e na sim), e o BulletReturnDetector vira um raio de
## 80px ao redor do canhão (muzzle real fica a ~270px, com folga).

const TARGET_SCENE := preload("res://components/target/target.tscn")
const BULLET_SCENE := preload("res://components/bullet/bullet.tscn")
## Cenas dos obstáculos via MaterialRules.scene_for (fonte única).

const TIMEOUT_FRAMES := 360 # 6 s a 60 ticks
const STOP_SPEED := 30.0
const STOP_FRAMES := 30
const RETURN_RADIUS := 80.0
const KILL_MARGIN := 400.0

var _target_hit := false
var _ricochets := 0
var _spawned: Array = [] # [{id: String, kind: StringName, node: Node}]


## Simula UM tiro. `state` tem o formato de LevelSolver.initial_state().
## Retorna {"hit_target": bool, "ricochets": int, "destroyed": Array[String],
##          "end_state": Dictionary, "frames": int, "termination": String
##          ("target"|"lost"|"returned"|"exited"|"stopped"|"timeout"),
##          "shard_count": int}.
func run_shot(def: LevelDefinition, state: Dictionary, angle: float, power: float) -> Dictionary:
	_build(def, state)

	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.contact_monitor = true
	bullet.max_contacts_reported = 16
	bullet.body_entered.connect(_on_bullet_body_entered)
	add_child(bullet)
	# Escala 1 (padrão da LevelDefinition v1): sem apply_cannon_scale.
	var muzzle_state := Cannon.muzzle_state_for(def.cannon_position, angle)
	bullet.global_position = muzzle_state["origin"] as Vector2
	var direction: Vector2 = muzzle_state["direction"]
	bullet.linear_velocity = direction * def.base_shot_speed * clampf(power, 0.0, 1.0)

	var termination := "timeout"
	var slow_frames := 0
	var kill_rect := def.play_bounds.grow(KILL_MARGIN)
	var frames := 0
	while frames < TIMEOUT_FRAMES:
		await get_tree().physics_frame
		frames += 1
		if _target_hit:
			termination = "target"
			break
		if not is_instance_valid(bullet):
			termination = "lost"
			break
		if frames > 2 and bullet.global_position.distance_to(def.cannon_position) < RETURN_RADIUS:
			termination = "returned"
			break
		if not kill_rect.has_point(bullet.global_position):
			termination = "exited"
			break
		if bullet.linear_velocity.length() < STOP_SPEED:
			slow_frames += 1
			if slow_frames >= STOP_FRAMES:
				termination = "stopped"
				break
		else:
			slow_frames = 0

	var destroyed: Array[String] = []
	var end_state := {"stone_hp": {}, "glass_alive": {}}
	for entry in _spawned:
		# Sem tipo: o Node pode ter sido liberado (vidro/pedra destruídos)
		# e atribuir instância liberada a var tipada dá erro de parse/exec.
		var node = entry["node"]
		if entry["kind"] == ObstacleDefinition.KIND_GLASS:
			var alive := is_instance_valid(node)
			end_state["glass_alive"][entry["id"]] = alive
			if not alive:
				destroyed.append(entry["id"])
		elif entry["kind"] == ObstacleDefinition.KIND_STONE:
			if not is_instance_valid(node):
				end_state["stone_hp"][entry["id"]] = 0
				destroyed.append(entry["id"])
			else:
				end_state["stone_hp"][entry["id"]] = (node as StoneObstacle).stoneLife

	var shards := 0
	for child in get_children():
		if child is Shard:
			shards += 1

	return {
		"hit_target": _target_hit,
		"ricochets": _ricochets,
		"destroyed": destroyed,
		"end_state": end_state,
		"frames": frames,
		"termination": termination,
		"shard_count": shards,
	}


func _build(def: LevelDefinition, state: Dictionary) -> void:
	_target_hit = false
	_ricochets = 0
	_spawned.clear()
	var stone_hp: Dictionary = state.get("stone_hp", {})
	var glass_alive: Dictionary = state.get("glass_alive", {})
	for obstacle in def.obstacles:
		match obstacle.kind:
			ObstacleDefinition.KIND_METAL:
				_spawned.append(_spawn(MaterialRules.scene_for(obstacle.kind), obstacle))
			ObstacleDefinition.KIND_STONE:
				var hp := int(stone_hp.get(obstacle.id, MaterialRules.max_hp(obstacle.kind)))
				if hp <= 0:
					continue
				var entry := _spawn(MaterialRules.scene_for(obstacle.kind), obstacle)
				var node := entry["node"] as StoneObstacle
				node.stoneLife = hp
				if hp == 1:
					(node.get_node("CrackedStone") as CanvasItem).visible = true
					(node.get_node("PolishedStone") as CanvasItem).visible = false
				_spawned.append(entry)
			ObstacleDefinition.KIND_GLASS:
				if not bool(glass_alive.get(obstacle.id, true)):
					continue
				_spawned.append(_spawn(MaterialRules.scene_for(obstacle.kind), obstacle))
			_:
				continue # kind inválido: o validador barra antes; a sim não quebra
	if def.target != null:
		var target := TARGET_SCENE.instantiate() as Target
		add_child(target)
		target.global_position = def.target.position
		target.hit.connect(_on_target_hit)


func _spawn(scene: PackedScene, obstacle: ObstacleDefinition) -> Dictionary:
	var node := scene.instantiate() as Node2D
	node.position = obstacle.position
	node.rotation_degrees = obstacle.rotation_degrees
	node.scale = obstacle.scale
	if "shard_count" in node:
		node.set("shard_count", 0)
	add_child(node)
	return {"id": obstacle.id, "kind": obstacle.kind, "node": node}


func _on_bullet_body_entered(body: Node) -> void:
	if body is MetalObstacle or body is StoneObstacle:
		_ricochets += 1


func _on_target_hit(_body: Bullet) -> void:
	_target_hit = true
