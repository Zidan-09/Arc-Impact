class_name FastLevelGenerator extends RefCounted
## Geração procedural em milissegundos, sem física (docs/plan.md).
## Orquestra composition-first: CompositionBuilder DESENHA, LevelValidator
## + validate_structure VERIFICAM (reprovam sem corrigir), o solver
## analítico ATESTA a jogabilidade com a assinatura mecânica declarada.
## O solver nunca desenha: só aprova ou rejeita a composição.
## Zero Nodes, zero `await physics_frame`, zero RNG global: mesma
## (seed, versão, fase) => mesma LevelDefinition. Porta de entrada da
## fase real (Game). Determinístico e offline (só matemática + geometria).
##
## Bandas com ricochete obrigatório usam o caminho legado (arquétipos)
## até a Etapa 8 entregar o vocabulário de ricochete ao compositor.
##
## Retorna {"def": LevelDefinition, "candidates": int, "sims": int (0),
##          "ms": int, "score": float, "fallback_used": bool,
##          "ultimate": bool, "log": Array[String]}.

const MAX_ATTEMPTS := 20
const TIME_BUDGET_MS := 250
const ANGLE_STEP := 2.0
const POWER_STEP := 0.1
const SIM_DT := 1.0 / 60.0
const SIM_MAX_STEPS := 360
const KILL_MARGIN := 400.0
const GROUND_TOP := 620.0
const TARGET_MAX_Y := 600.0 # alvo apoiado no plano (centro 580) + folga
const REST_TOL := 2.0 # [TÉCNICO] peça APOIADA no floor encosta (end ~620)
const BULLET_RADIUS := 10.0
const MAX_RICOCHETS := 10
## Colisor real do alvo em scale 0.2: polígono de target.tscn tem
## 114x474px na base => ~23x95px instanciado (NÃO 80x80: o
## TargetDefinition.DEFAULT_SIZE é aproximação conservadora só para o
## validador). O solver usa estas medidas + rotação, dilatadas pelo raio
## da bala — acerto analítico precisa implicar acerto real.
const TARGET_BODY := Vector2(23.0, 95.0)


static func generate(seed_value: int, level_number: int, cfg_override: DifficultyConfig = null) -> Dictionary:
	var cfg: DifficultyConfig = cfg_override if cfg_override != null else DifficultyTable.get_config(level_number)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d" % [seed_value, LevelDefinition.GENERATOR_VERSION, level_number])
	var log: Array[String] = []
	var start := Time.get_ticks_msec()
	if cfg.required_ricochets_min > 0:
		# Etapa 8: sem vocabulário de ricochete no compositor, bandas
		# 11+ seguem no caminho legado (solver como filtro, como antes).
		log.append("legacy-band")
		return _generate_legacy(seed_value, level_number, cfg, rng, start, log)
	var tried := 0
	for _attempt in MAX_ATTEMPTS:
		if Time.get_ticks_msec() - start > TIME_BUDGET_MS:
			log.append("budget")
			break
		tried += 1
		var def := CompositionBuilder.build(rng, cfg, seed_value, level_number)
		var tags := _tag_string(def)
		if not bool(LevelValidator.validate(def)["ok"]):
			log.append("validate:composer:" + tags)
			continue
		if not bool(LevelValidator.validate_structure(def)["ok"]):
			log.append("structure:composer:" + tags)
			continue
		if not bool(LevelValidator.validate_config(def, cfg)["ok"]):
			log.append("config:composer:" + tags)
			continue
		var record := solve_direct(def, start)
		if record == null:
			log.append("unsolved:composer:" + tags)
			continue
		if record.total_shots > def.ammo:
			log.append("ammo:composer:" + tags)
			continue
		if not _mechanic_signature_ok(def, record):
			log.append("mechanic:composer:" + tags)
			continue
		if not _robust_analytic(def, record):
			log.append("margin:composer:" + tags)
			continue
		var score := DifficultyScorer.score(def, record)
		if not DifficultyScorer.in_band(score, cfg):
			log.append("score:%.2f" % score)
			continue
		def.solution = record
		log.append("composer:" + tags)
		return _report(def, tried, start, score, false, false, log)
	var ultimate := _ultimate(seed_value, level_number, cfg)
	var ultimate_score := -1.0
	if ultimate.solution != null:
		ultimate_score = DifficultyScorer.score(ultimate, ultimate.solution)
	return _report(ultimate, tried, start, ultimate_score, true, true, log)


## Caminho legado (arquétipos de pontos aleatórios + solver como filtro).
## Mantido só para bandas com ricochete até a Etapa 8. Não alterar.
static func _generate_legacy(seed_value: int, level_number: int, cfg: DifficultyConfig, rng: RandomNumberGenerator, start: int, log: Array[String]) -> Dictionary:
	var tried := 0
	for _attempt in MAX_ATTEMPTS:
		if Time.get_ticks_msec() - start > TIME_BUDGET_MS:
			log.append("budget")
			break
		tried += 1
		var arch := _pick_archetype(rng, cfg)
		if arch == null:
			log.append("no-archetype")
			break
		var def := _skeleton(seed_value, level_number, cfg)
		if not arch.place(def, rng, cfg):
			log.append("placement:" + String(arch.id()))
			continue
		if not _clear_of_ground(def):
			log.append("ground:" + String(arch.id()))
			continue
		if not bool(LevelValidator.validate(def)["ok"]):
			log.append("validate:" + String(arch.id()))
			continue
		if not bool(LevelValidator.validate_config(def, cfg)["ok"]):
			log.append("config:" + String(arch.id()))
			continue
		var record := solve_direct(def, start)
		if record == null:
			log.append("unsolved:" + String(arch.id()))
			continue
		if record.total_shots > def.ammo:
			log.append("ammo:" + String(arch.id()))
			continue
		if record.total_ricochets < cfg.required_ricochets_min:
			log.append("ricochet:" + String(arch.id()))
			continue
		var score := DifficultyScorer.score(def, record)
		if not DifficultyScorer.in_band(score, cfg):
			log.append("score:%.2f" % score)
			continue
		def.solution = record
		return _report(def, tried, start, score, false, false, log)
	var ultimate := _ultimate(seed_value, level_number, cfg)
	var ultimate_score := -1.0
	if ultimate.solution != null:
		ultimate_score = DifficultyScorer.score(ultimate, ultimate.solution)
	return _report(ultimate, tried, start, ultimate_score, true, true, log)


## Assinatura mecânica: se a composição declara quebra/desgaste, o
## caminho vencedor precisa exibir a peça com função destruída. Sem
## peça funcional declarada (só moldura), qualquer solução vale.
static func _mechanic_signature_ok(def: LevelDefinition, record: SolutionRecord) -> bool:
	var declared := {}
	for obstacle in def.obstacles:
		if obstacle.mechanic != Composition.MECH_FRAME:
			declared[obstacle.id] = true
	if declared.is_empty():
		return true
	for shot in record.shots:
		for id in Array(shot.get("destroyed", [])):
			if declared.has(String(id)):
				return true
	return false


static func _tag_string(def: LevelDefinition) -> String:
	var parts: Array[String] = []
	for tag in def.composition_tags:
		parts.append(String(tag))
	return ",".join(parts)


## Robustez analítica (espelha LevelSolver._probe_margin): a sequência
## vencedora precisa vencer também com o 1º tiro perturbado ±0.5°.
## Solução de raspão (só passa no fio) é rejeitada aqui — barata no
## analítico, cara na física real. Só aprova o robusto.
static func _robust_analytic(def: LevelDefinition, record: SolutionRecord) -> bool:
	if record.shots.is_empty():
		return false
	var first: Dictionary = record.shots[0]
	var angle := float(first["angle"])
	var power := float(first["power"])
	for delta in [0.5, -0.5]:
		var perturbed := _try_sequence_perturbed(def, angle, power, delta)
		if perturbed == null:
			return false
	return true


## Variante de _try_sequence com o 1º tiro perturbado em `delta` graus
## (limitado aos ângulos do canhão). Retorna SolutionRecord ou null.
static func _try_sequence_perturbed(def: LevelDefinition, angle: float, power: float, delta: float) -> SolutionRecord:
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var kill_rect := def.play_bounds.grow(KILL_MARGIN)
	var target_rect := target_rect_for(def)
	var perturbed_angle := clampf(angle + delta, def.cannon_angle_min, def.cannon_angle_max)
	var stone_hp := {}
	var glass_alive := {}
	for obstacle in def.obstacles:
		if obstacle.kind == ObstacleDefinition.KIND_STONE:
			stone_hp[obstacle.id] = MaterialRules.max_hp(obstacle.kind)
		elif obstacle.kind == ObstacleDefinition.KIND_GLASS:
			glass_alive[obstacle.id] = true
	var shots: Array[Dictionary] = []
	for _shot in maxi(def.ammo, 1):
		var boxes := _boxes_for_state(def, stone_hp, glass_alive)
		var sim := _simulate_shot(def, boxes, stone_hp, glass_alive, target_rect, kill_rect, gravity, perturbed_angle, power)
		shots.append({"angle": perturbed_angle, "power": power,
			"ricochets": int(sim["ricochets"]), "destroyed": Array(sim["destroyed"])})
		if bool(sim["hit_target"]):
			var record := SolutionRecord.new()
			record.shots = shots
			record.total_shots = shots.size()
			record.total_ricochets = 0
			record.solutions_found = 1
			return record
		if Array(sim["destroyed"]).is_empty() and not bool(sim["cracked"]):
			return null
	return null


## Retângulo do alvo para o solver: AABB do corpo real sob a rotação da
## composição, dilatado pelo raio da bala (mesmo tratamento dos
## obstáculos). Ver TARGET_BODY.
static func target_rect_for(def: LevelDefinition) -> Rect2:
	var rot := deg_to_rad(def.target.rotation_degrees)
	var w := TARGET_BODY.x * absf(cos(rot)) + TARGET_BODY.y * absf(sin(rot))
	var h := TARGET_BODY.x * absf(sin(rot)) + TARGET_BODY.y * absf(cos(rot))
	return Rect2(def.target.position - Vector2(w, h) * 0.5, Vector2(w, h)).grow(BULLET_RADIUS)


## Varredura analítica da trajetória (Euler 60 Hz, sem Nodes), fiel à
## física real (MaterialRules + *_obstacle.gd):
## - vidro: destrói no toque, atravessa com *= 0.85 (Area2D, sem rebote);
## - pedra HP2: 1º toque RACHA e REBATE (bounce 1.0 do motor, corpo fica);
##   2º toque (HP1) destrói e atravessa com *= 0.85;
## - metal: reflete (bounce 1.0, faces do AABB como espelhos planos).
## Multi-tiro COM ESTADO: se um tiro quebra/desgasta mas erra o alvo, o
## MESMO (ângulo, potência) é re-simulado com o estado persistido
## (vidro fora, pedra HP1), até `def.ammo` tiros — como o jogador faria
## (quebrar a junta no 1º tiro, passar no 2º). O registro sai com a
## sequência real de tiros, reproduzível na física (proof test).
## Retorna SolutionRecord ou null. Respeita o orçamento de wall-clock.
## AABBs dilatados pelo raio da bala (~10px em escala 0.2).
static func solve_direct(def: LevelDefinition, start_ms: int = -1) -> SolutionRecord:
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var kill_rect := def.play_bounds.grow(KILL_MARGIN)
	if def.target == null:
		return null
	var target_rect := target_rect_for(def)
	var angle := def.cannon_angle_min
	while angle <= def.cannon_angle_max + 0.001:
		var power := def.power_max
		while power >= def.power_min - 0.001:
			if start_ms >= 0 and Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
				return null
			var record := _try_sequence(def, target_rect, kill_rect, gravity, angle, power)
			if record != null:
				return record
			power -= POWER_STEP
		angle += ANGLE_STEP
	return null


## Tenta (ângulo, potência) em até `def.ammo` tiros sequenciais com HP
## persistido. Retorna o registro da sequência vencedora ou null.
static func _try_sequence(def: LevelDefinition, target_rect: Rect2, kill_rect: Rect2, gravity: float, angle: float, power: float) -> SolutionRecord:
	var stone_hp := {}
	var glass_alive := {}
	for obstacle in def.obstacles:
		if obstacle.kind == ObstacleDefinition.KIND_STONE:
			stone_hp[obstacle.id] = MaterialRules.max_hp(obstacle.kind)
		elif obstacle.kind == ObstacleDefinition.KIND_GLASS:
			glass_alive[obstacle.id] = true
	var shots: Array[Dictionary] = []
	var total_ricochets := 0
	for _shot in maxi(def.ammo, 1):
		var boxes := _boxes_for_state(def, stone_hp, glass_alive)
		var sim := _simulate_shot(def, boxes, stone_hp, glass_alive, target_rect, kill_rect, gravity, angle, power)
		total_ricochets += int(sim["ricochets"])
		shots.append({"angle": angle, "power": power,
			"ricochets": int(sim["ricochets"]),
			"destroyed": Array(sim["destroyed"])})
		if bool(sim["hit_target"]):
			var record := SolutionRecord.new()
			record.shots = shots
			record.total_shots = shots.size()
			record.total_ricochets = total_ricochets
			record.solutions_found = 1
			record.min_angle_margin = 0.25
			return record
		if Array(sim["destroyed"]).is_empty() and not bool(sim["cracked"]):
			return null # sem progresso: repetir não muda nada
	return null


## Caixas dos obstáculos vivos no estado (pedra HP0 e vidro destruído
## saem — o projétil atravessa onde já destruiu).
static func _boxes_for_state(def: LevelDefinition, stone_hp: Dictionary, glass_alive: Dictionary) -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	for obstacle in def.obstacles:
		if obstacle.kind == ObstacleDefinition.KIND_STONE and int(stone_hp.get(obstacle.id, 0)) <= 0:
			boxes.append(Rect2())
		elif obstacle.kind == ObstacleDefinition.KIND_GLASS and not bool(glass_alive.get(obstacle.id, true)):
			boxes.append(Rect2())
		else:
			boxes.append(LevelValidator.obstacle_aabb(obstacle).grow(BULLET_RADIUS))
	return boxes


## Simula UM tiro no estado dado (e o atualiza: vidro some, pedra perde
## HP). Retorna {"hit_target", "ricochets", "destroyed": [ids do tiro],
## "cracked": bool (rachou pedra sem destruir)}.
static func _simulate_shot(def: LevelDefinition, boxes: Array[Rect2], stone_hp: Dictionary, glass_alive: Dictionary, target_rect: Rect2, kill_rect: Rect2, gravity: float, angle: float, power: float) -> Dictionary:
	var muzzle := Cannon.muzzle_state_for(def.cannon_position, angle)
	var pos: Vector2 = muzzle["origin"]
	var vel: Vector2 = (muzzle["direction"] as Vector2) * def.base_shot_speed * clampf(power, 0.0, 1.0)
	var ricochets := 0
	var cracked := false
	var destroyed: Array[String] = []
	var gone := {} # destruídas NESTE tiro (snapshot de caixas é por tiro)
	for _step in SIM_MAX_STEPS:
		vel += Vector2(0, gravity) * SIM_DT
		var next := pos + vel * SIM_DT
		if _segment_hits_rect(pos, next, target_rect):
			return {"hit_target": true, "ricochets": ricochets, "destroyed": destroyed, "cracked": cracked}
		var nearest := -1
		var nearest_face := Vector2.ZERO
		var nearest_dist := INF
		for i in def.obstacles.size():
			if boxes[i].size == Vector2.ZERO:
				continue
			if gone.has(def.obstacles[i].id):
				continue
			var face := _entry_face(pos, next, boxes[i])
			if face == Vector2.ZERO:
				continue
			var contact := _contact_point(pos, next, boxes[i], face)
			var dist: float = pos.distance_to(contact)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = i
				nearest_face = face
		if nearest >= 0:
			var id: String = def.obstacles[nearest].id
			match def.obstacles[nearest].kind:
				ObstacleDefinition.KIND_METAL:
					if ricochets >= MAX_RICOCHETS:
						return {"hit_target": false, "ricochets": ricochets, "destroyed": destroyed, "cracked": cracked}
					pos = _contact_point(pos, next, boxes[nearest], nearest_face)
					vel = _reflect(vel, nearest_face)
					ricochets += 1
					if pos.y > GROUND_TOP or not kill_rect.has_point(pos):
						return {"hit_target": false, "ricochets": ricochets, "destroyed": destroyed, "cracked": cracked}
					continue
				ObstacleDefinition.KIND_STONE:
					ricochets += 1 # a física conta o contato da pedra
					if int(stone_hp.get(id, 2)) > 1:
						stone_hp[id] = int(stone_hp.get(id, 2)) - 1
						cracked = true
						pos = _contact_point(pos, next, boxes[nearest], nearest_face)
						vel = _reflect(vel, nearest_face) # 1º toque rebate
						if pos.y > GROUND_TOP or not kill_rect.has_point(pos):
							return {"hit_target": false, "ricochets": ricochets, "destroyed": destroyed, "cracked": cracked}
						continue
					stone_hp[id] = 0
					gone[id] = true
					vel *= MaterialRules.velocity_retain(def.obstacles[nearest].kind)
					destroyed.append(id)
				_:
					glass_alive[id] = false
					gone[id] = true
					vel *= MaterialRules.velocity_retain(def.obstacles[nearest].kind)
					destroyed.append(id)
		pos = next
		if pos.y > GROUND_TOP:
			return {"hit_target": false, "ricochets": ricochets, "destroyed": destroyed, "cracked": cracked}
		if not kill_rect.has_point(pos):
			return {"hit_target": false, "ricochets": ricochets, "destroyed": destroyed, "cracked": cracked}
	return {"hit_target": false, "ricochets": ricochets, "destroyed": destroyed, "cracked": cracked}


static func _pick_archetype(rng: RandomNumberGenerator, cfg: DifficultyConfig) -> LevelArchetype:
	var options: Array[LevelArchetype] = []
	for archetype_id in cfg.allowed_archetypes:
		var arch := ProceduralLevelGenerator.make_archetype(archetype_id)
		if arch != null and arch.min_ammo() <= cfg.ammo:
			options.append(arch)
	if options.is_empty():
		return null
	return options[rng.randi_range(0, options.size() - 1)]


static func _skeleton(seed_value: int, level_number: int, cfg: DifficultyConfig) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = cfg.ammo
	def.world_bounds = def.play_bounds
	return def


## Chão do Builder (faixa y 620..720): peças APOIADAS encostam
## (end ~620 + REST_TOL); o validador estrutural conhece a geometria do
## Ground — este filtro só barra peça enterrada ou alvo fora da faixa.
static func _clear_of_ground(def: LevelDefinition) -> bool:
	if def.target != null and def.target.position.y > TARGET_MAX_Y:
		return false
	for obstacle in def.obstacles:
		if LevelValidator.obstacle_aabb(obstacle).end.y > GROUND_TOP + REST_TOL:
			return false
	return true


static func _ultimate(seed_value: int, level_number: int, cfg: DifficultyConfig) -> LevelDefinition:
	var def := ProceduralLevelGenerator.ultimate_fallback(seed_value, level_number, cfg)
	def.solution = solve_direct(def)
	return def


static func _report(def: LevelDefinition, tried: int, start: int, score: float, fallback_used: bool, ultimate: bool, log: Array[String]) -> Dictionary:
	return {
		"def": def,
		"candidates": tried,
		"sims": 0,
		"ms": Time.get_ticks_msec() - start,
		"score": score,
		"fallback_used": fallback_used,
		"ultimate": ultimate,
		"log": log,
	}


static func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		var hit = Geometry2D.segment_intersects_segment(from, to, corners[i], corners[(i + 1) % 4])
		if hit != null:
			return true
	return false


## Face do AABB atingida pelo segmento (método do espelho por faces:
## cada face é um espelho plano; bounce 1.0 do metal => reflexão exata).
## Retorna a normal (LEFT/RIGHT/UP/DOWN) ou Vector2.ZERO sem interseção.
static func _entry_face(from: Vector2, to: Vector2, rect: Rect2) -> Vector2:
	if rect.has_point(from):
		return Vector2.ZERO
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2.UP],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2.DOWN],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2.LEFT],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2.RIGHT],
	]
	var best := Vector2.ZERO
	var best_dist := INF
	for edge in edges:
		var hit = Geometry2D.segment_intersects_segment(from, to, edge[0], edge[1])
		if hit != null:
			var dist: float = from.distance_to(hit)
			if dist < best_dist:
				best_dist = dist
				best = edge[2]
	return best


static func _contact_point(from: Vector2, to: Vector2, rect: Rect2, face: Vector2) -> Vector2:
	var edge := [rect.position, rect.position]
	if face == Vector2.UP:
		edge = [Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y)]
	elif face == Vector2.DOWN:
		edge = [Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y)]
	elif face == Vector2.LEFT:
		edge = [Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y)]
	else:
		edge = [Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y)]
	var hit = Geometry2D.segment_intersects_segment(from, to, edge[0], edge[1])
	if hit != null:
		return hit
	return to


static func _reflect(vel: Vector2, normal: Vector2) -> Vector2:
	return vel - 2.0 * vel.dot(normal) * normal
