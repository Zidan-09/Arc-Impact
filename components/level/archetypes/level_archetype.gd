class_name LevelArchetype extends RefCounted
## Base dos arquétipos de fase (Etapa 6, docs/plan.md §9).
## Cada arquétipo posiciona alvo + obstáculos num LevelDefinition vazio,
## usando SÓ o rng com seed (nunca RNG global). `place()` retorna false
## se o motivo não couber na config — o gerador tenta outro candidato.
## Convenção: alvo primeiro, depois obstáculos; ids "obs_%02d".
## Escalas fixas na v1 (vidro 0.1, pedra/metal 0.2); rotações 0°.

const GLASS_SCALE := Vector2(0.1, 0.1)
const BLOCK_SCALE := Vector2(0.2, 0.2)
const LANE_CLEARANCE := 70.0 # raio do bullet (~46) + folga
const PLACE_ATTEMPTS := 20
const EDGE_MARGIN := 80.0


func id() -> StringName:
	return &"base"


func min_ammo() -> int:
	return 1


func place(_def: LevelDefinition, _rng: RandomNumberGenerator, _cfg: DifficultyConfig) -> bool:
	return false


func spot_target(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf_range(950.0, 1200.0), rng.randf_range(80.0, 640.0))


func set_target(def: LevelDefinition, pos: Vector2) -> void:
	def.target = TargetDefinition.new()
	def.target.position = pos


static func seg_dist(point: Vector2, from: Vector2, to: Vector2) -> float:
	var delta := to - from
	if delta.length_squared() < 0.0001:
		return point.distance_to(from)
	var t := clampf((point - from).dot(delta) / delta.length_squared(), 0.0, 1.0)
	return point.distance_to(from + delta * t)


func half_diag(kind: StringName, scale: Vector2) -> float:
	return (MaterialRules.base_size(kind) * scale).length() * 0.5


## Espelha os limiares do LevelValidator (limites, exclusão do canhão
## e do alvo, sobreposição) para só propor o que tem chance de passar.
func fits(def: LevelDefinition, kind: StringName, pos: Vector2, scale: Vector2, rot: float = 0.0) -> bool:
	var probe := ObstacleDefinition.new()
	probe.kind = kind
	probe.position = pos
	probe.scale = scale
	probe.rotation_degrees = rot
	var box := LevelValidator.obstacle_aabb(probe)
	if not def.play_bounds.encloses(box):
		return false
	if _point_rect_dist(def.cannon_position, box) < LevelValidator.CANNON_EXCLUSION:
		return false
	if def.target != null:
		var zone := Rect2(def.target.position - def.target.size * 0.5, def.target.size).grow(LevelValidator.TARGET_EXCLUSION)
		if box.intersects(zone):
			return false
	for existing in def.obstacles:
		if not MaterialRules.is_known(existing.kind):
			continue
		var margin := LevelValidator.OVERLAP_MARGIN * 0.5
		if box.grow(margin).intersects(LevelValidator.obstacle_aabb(existing).grow(margin)):
			return false
	return true


func add_ob(def: LevelDefinition, kind: StringName, pos: Vector2, scale: Vector2, rot: float = 0.0) -> ObstacleDefinition:
	var ob := ObstacleDefinition.new()
	ob.id = "obs_%02d" % (def.obstacles.size() + 1)
	ob.kind = kind
	ob.position = pos
	ob.scale = scale
	ob.rotation_degrees = rot
	def.obstacles.append(ob)
	return ob


func rollback(def: LevelDefinition, before: int) -> void:
	while def.obstacles.size() > before:
		def.obstacles.pop_back()


func count_in(rng: RandomNumberGenerator, band: Vector2i) -> int:
	return rng.randi_range(band.x, band.y)


func rand_point(rng: RandomNumberGenerator, bounds: Rect2) -> Vector2:
	return Vector2(
		rng.randf_range(bounds.position.x + EDGE_MARGIN, bounds.end.x - EDGE_MARGIN),
		rng.randf_range(bounds.position.y + EDGE_MARGIN, bounds.end.y - EDGE_MARGIN))


## true se `pos` (com meia-diagonal) invade a faixa canhão->alvo.
func lane_hit(pos: Vector2, half_diag: float, from: Vector2, to: Vector2) -> bool:
	return seg_dist(pos, from, to) < LANE_CLEARANCE + half_diag


## `count` obstáculos SOBRE a faixa (t entre t_min e t_max + jitter).
func place_on_lane(def: LevelDefinition, rng: RandomNumberGenerator, kind: StringName, scale: Vector2, count: int, t_min: float = 0.3, t_max: float = 0.7, jitter: float = 25.0) -> bool:
	var before := def.obstacles.size()
	var from := def.cannon_position
	var to := def.target.position
	var delta := to - from
	var length := delta.length()
	var dir := delta / length
	var normal := Vector2(-dir.y, dir.x)
	for _i in count:
		var done := false
		for _j in PLACE_ATTEMPTS:
			var t := rng.randf_range(t_min, t_max)
			var pos := from + dir * (length * t) + normal * rng.randf_range(-jitter, jitter)
			if fits(def, kind, pos, scale):
				add_ob(def, kind, pos, scale)
				done = true
				break
		if not done:
			rollback(def, before)
			return false
	return true


## `count` obstáculos FORA da faixa.
func place_off_lane(def: LevelDefinition, rng: RandomNumberGenerator, kind: StringName, scale: Vector2, count: int) -> bool:
	var before := def.obstacles.size()
	var half := half_diag(kind, scale)
	for _i in count:
		var done := false
		for _j in PLACE_ATTEMPTS:
			var pos := rand_point(rng, def.play_bounds)
			if lane_hit(pos, half, def.cannon_position, def.target.position):
				continue
			if fits(def, kind, pos, scale):
				add_ob(def, kind, pos, scale)
				done = true
				break
		if not done:
			rollback(def, before)
			return false
	return true


func _point_rect_dist(point: Vector2, rect: Rect2) -> float:
	var clamped := Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(clamped)
