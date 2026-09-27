class_name FastLevelGenerator extends RefCounted
## Geração procedural em milissegundos, sem física (docs/plan.md §3/§5).
## Solução PRIMEIRO (balística analítica), obstáculos DEPOIS preservando
## o corredor da solução; LevelValidator como guarda geométrico.
## Zero Nodes, zero `await physics_frame`, zero RNG global: mesma
## (seed, versão, fase) => mesma LevelDefinition. Porta de entrada da
## fase real (Game); o ProceduralLevelGenerator lento vira ferramenta
## offline/teste. Determinístico e offline (só matemática + geometria).
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
const TARGET_MAX_Y := 575.0
const GROUND_CLEARANCE := 5.0
const BULLET_RADIUS := 10.0
const MAX_RICOCHETS := 10


static func generate(seed_value: int, level_number: int, cfg_override: DifficultyConfig = null) -> Dictionary:
	var cfg: DifficultyConfig = cfg_override if cfg_override != null else DifficultyTable.get_config(level_number)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d" % [seed_value, LevelDefinition.GENERATOR_VERSION, level_number])
	var log: Array[String] = []
	var start := Time.get_ticks_msec()
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


## Varredura analítica da trajetória (Euler 60 Hz, sem Nodes): vidro e
## pedra atravessam com *= 0.85 (MaterialRules); cada pedra custa +1 tiro
## (1º tiro racha, 2º atravessa); metal reflete (bounce 1.0 do motor,
## sem atenuação por código; faces do AABB como espelhos planos).
## Retorna SolutionRecord com 1 tiro base ou null. Respeita o orçamento
## de wall-clock. AABBs dilatados pelo raio da bala (~10px em escala 0.2).
static func solve_direct(def: LevelDefinition, start_ms: int = -1) -> SolutionRecord:
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var kill_rect := def.play_bounds.grow(KILL_MARGIN)
	var target_rect := Rect2(def.target.position - def.target.size * 0.5, def.target.size) if def.target != null else Rect2()
	if def.target == null:
		return null
	var boxes: Array[Rect2] = []
	for obstacle in def.obstacles:
		boxes.append(LevelValidator.obstacle_aabb(obstacle).grow(BULLET_RADIUS))
	var angle := def.cannon_angle_min
	while angle <= def.cannon_angle_max + 0.001:
		var power := def.power_max
		while power >= def.power_min - 0.001:
			if start_ms >= 0 and Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
				return null
			var record := _try_shot(def, boxes, target_rect, kill_rect, gravity, angle, power)
			if record != null:
				return record
			power -= POWER_STEP
		angle += ANGLE_STEP
	return null


static func _try_shot(def: LevelDefinition, boxes: Array[Rect2], target_rect: Rect2, kill_rect: Rect2, gravity: float, angle: float, power: float) -> SolutionRecord:
	var muzzle := Cannon.muzzle_state_for(def.cannon_position, angle)
	var pos: Vector2 = muzzle["origin"]
	var vel: Vector2 = (muzzle["direction"] as Vector2) * def.base_shot_speed * clampf(power, 0.0, 1.0)
	var touched := {}
	var stones := 0
	var ricochets := 0
	var destroyed: Array[String] = []
	for _step in SIM_MAX_STEPS:
		vel += Vector2(0, gravity) * SIM_DT
		var next := pos + vel * SIM_DT
		if _segment_hits_rect(pos, next, target_rect):
			var record := SolutionRecord.new()
			record.shots = [{"angle": angle, "power": power, "ricochets": ricochets, "destroyed": destroyed}]
			record.total_shots = 1 + stones
			record.total_ricochets = ricochets
			record.solutions_found = 1
			record.min_angle_margin = 0.25
			return record
		var bounced := false
		var nearest := -1
		var nearest_face := Vector2.ZERO
		var nearest_dist := INF
		for i in def.obstacles.size():
			var id: String = def.obstacles[i].id
			if touched.has(id):
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
						return null
					pos = _contact_point(pos, next, boxes[nearest], nearest_face)
					vel = _reflect(vel, nearest_face)
					ricochets += 1
					bounced = true
				ObstacleDefinition.KIND_STONE:
					stones += 1
					vel *= MaterialRules.velocity_retain(def.obstacles[nearest].kind)
					touched[id] = true
					destroyed.append(id)
				_:
					vel *= MaterialRules.velocity_retain(def.obstacles[nearest].kind)
					touched[id] = true
					destroyed.append(id)
		if bounced:
			if pos.y > GROUND_TOP:
				return null
			if not kill_rect.has_point(pos):
				return null
			continue
		pos = next
		if pos.y > GROUND_TOP:
			return null
		if not kill_rect.has_point(pos):
			return null
	return null


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
	return def


## Chão do Builder (faixa y 620..720, Guide R2): alvo e obstáculos ficam
## acima dele; o validador atual não conhece o chão, então o filtro vive
## aqui até o validador aprender a geometria do Ground.
static func _clear_of_ground(def: LevelDefinition) -> bool:
	if def.target != null and def.target.position.y > TARGET_MAX_Y:
		return false
	for obstacle in def.obstacles:
		if LevelValidator.obstacle_aabb(obstacle).end.y > GROUND_TOP - GROUND_CLEARANCE:
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
