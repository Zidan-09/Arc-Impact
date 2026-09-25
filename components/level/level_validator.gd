class_name LevelValidator extends RefCounted
## Validação estrutural barata, sem física (Etapa 3, docs/plan.md §6).
## Reprova rápido o que é geometricamente errado; a solucionabilidade
## final é do LevelSolver (Etapa 4+). Retorna sempre:
## {"ok": bool, "errors": Array[String], "warnings": Array[String]}.
## Geometria aproximada por AABB (`base_size * scale`, 0/90°); o vidro
## usa a hitbox atravessável como área ocupada (conservador).

const ERR_OUT_OF_BOUNDS := "OUT_OF_BOUNDS"
const ERR_MISSING_TARGET := "MISSING_TARGET"
const ERR_OVERLAP_CANNON := "OVERLAP_CANNON"
const ERR_OVERLAP_TARGET := "OVERLAP_TARGET"
const ERR_OVERLAP_OBSTACLE := "OVERLAP_OBSTACLE"
const ERR_TARGET_TOO_CLOSE := "TARGET_TOO_CLOSE"
const ERR_TARGET_BOXED := "TARGET_BOXED"
const ERR_MUZZLE_BLOCKED := "MUZZLE_BLOCKED"
const ERR_INVALID_KIND := "INVALID_KIND"
const ERR_INVALID_ROTATION := "INVALID_ROTATION"
const ERR_INVALID_SCALE := "INVALID_SCALE"
const ERR_INVALID_AMMO := "INVALID_AMMO"
const ERR_UNSUPPORTED_VERSION := "UNSUPPORTED_VERSION"
const ERR_CONFIG_AMMO_MISMATCH := "CONFIG_AMMO_MISMATCH"
const ERR_CONFIG_COUNT_OUT_OF_RANGE := "CONFIG_COUNT_OUT_OF_RANGE"
const WARN_NO_RICOCHET_SUPPORT := "WARN_NO_RICOCHET_SUPPORT"

const CANNON_EXCLUSION := 150.0
const TARGET_EXCLUSION := 100.0
const OVERLAP_MARGIN := 8.0
const MIN_CANNON_TARGET_DIST := 500.0
const BOXED_RAY_LENGTH := 200.0
# Corredor aproximado cano->boca para tiro padrão 45° em escala 1
# (muzzle real ~= canhão + (265, -50)). A Etapa 7 refina com o
# transform vivo do canhão; aqui vale como guarda contra spawn morto.
const MUZZLE_CORRIDOR := Vector2(280, -60)


static func validate(def: LevelDefinition) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if def.generator_version != LevelDefinition.GENERATOR_VERSION:
		errors.append(ERR_UNSUPPORTED_VERSION)
		return _result(errors, warnings)

	if def.ammo < 1 or def.ammo > 4:
		errors.append(ERR_INVALID_AMMO)

	if not def.play_bounds.has_point(def.cannon_position):
		errors.append(ERR_OUT_OF_BOUNDS)

	if def.target == null:
		errors.append(ERR_MISSING_TARGET)
	else:
		var target_rect := _target_rect(def.target)
		if not _rect_inside(target_rect, def.play_bounds):
			errors.append(ERR_OUT_OF_BOUNDS)
		if def.cannon_position.distance_to(def.target.position) < MIN_CANNON_TARGET_DIST:
			errors.append(ERR_TARGET_TOO_CLOSE)

	var boxes: Array[Rect2] = []
	for obstacle in def.obstacles:
		if not MaterialRules.is_known(obstacle.kind):
			errors.append(ERR_INVALID_KIND)
			boxes.append(Rect2())
			continue
		if not is_valid_rotation(obstacle.rotation_degrees):
			errors.append(ERR_INVALID_ROTATION)
		if not is_valid_scale(obstacle.scale):
			errors.append(ERR_INVALID_SCALE)
		var box := obstacle_aabb(obstacle)
		boxes.append(box)
		if not _rect_inside(box, def.play_bounds):
			errors.append(ERR_OUT_OF_BOUNDS)
		if _dist_point_to_rect(def.cannon_position, box) < CANNON_EXCLUSION:
			errors.append(ERR_OVERLAP_CANNON)
		if def.target != null:
			var target_zone := _target_rect(def.target).grow(TARGET_EXCLUSION)
			if box.intersects(target_zone):
				errors.append(ERR_OVERLAP_TARGET)
		var corridor_end := def.cannon_position + MUZZLE_CORRIDOR
		if _segment_hits_rect(def.cannon_position, corridor_end, box):
			errors.append(ERR_MUZZLE_BLOCKED)

	for i in def.obstacles.size():
		for j in range(i + 1, def.obstacles.size()):
			if boxes[i].size == Vector2.ZERO or boxes[j].size == Vector2.ZERO:
				continue
			var margin := OVERLAP_MARGIN * 0.5
			if boxes[i].grow(margin).intersects(boxes[j].grow(margin)):
				errors.append(ERR_OVERLAP_OBSTACLE)

	if def.target != null and _target_boxed(def, boxes):
		errors.append(ERR_TARGET_BOXED)

	return _result(errors, warnings)


## Coerência da fase com a DifficultyConfig (contagens e munição).
static func validate_config(def: LevelDefinition, cfg: DifficultyConfig) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if def.ammo != cfg.ammo:
		errors.append(ERR_CONFIG_AMMO_MISMATCH)
	var counts := {ObstacleDefinition.KIND_GLASS: 0, ObstacleDefinition.KIND_STONE: 0, ObstacleDefinition.KIND_METAL: 0}
	for obstacle in def.obstacles:
		if counts.has(obstacle.kind):
			counts[obstacle.kind] += 1
	var ranges := {
		ObstacleDefinition.KIND_GLASS: cfg.glass_count,
		ObstacleDefinition.KIND_STONE: cfg.stone_count,
		ObstacleDefinition.KIND_METAL: cfg.metal_count,
	}
	for kind in ranges:
		var expected: Vector2i = ranges[kind]
		var found: int = counts[kind]
		if found < expected.x or found > expected.y:
			errors.append(ERR_CONFIG_COUNT_OUT_OF_RANGE)
	if cfg.required_ricochets_min > 0 and cfg.metal_count.y == 0:
		warnings.append(WARN_NO_RICOCHET_SUPPORT)
	return _result(errors, warnings)


## AABB aproximado: base_size * scale, com 90° trocando largura/altura.
static func obstacle_aabb(obstacle: ObstacleDefinition) -> Rect2:
	var size := MaterialRules.base_size(obstacle.kind) * obstacle.scale
	if absf(wrapf(obstacle.rotation_degrees, 0.0, 180.0) - 90.0) < 0.01:
		size = Vector2(size.y, size.x)
	return Rect2(obstacle.position - size * 0.5, size)


static func is_valid_rotation(rotation_degrees: float) -> bool:
	var wrapped := absf(wrapf(rotation_degrees, 0.0, 180.0))
	return wrapped < 0.01 or absf(wrapped - 90.0) < 0.01


static func is_valid_scale(scale: Vector2) -> bool:
	return scale.x >= 0.05 and scale.x <= 1.0 and scale.y >= 0.05 and scale.y <= 1.0


static func _result(errors: Array[String], warnings: Array[String]) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func _target_rect(target: TargetDefinition) -> Rect2:
	return Rect2(target.position - target.size * 0.5, target.size)


static func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.encloses(inner)


static func _dist_point_to_rect(point: Vector2, rect: Rect2) -> float:
	var clamped := Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)
	return point.distance_to(clamped)


static func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		var hit = Geometry2D.segment_intersects_segment(from, to, corners[i], corners[(i + 1) % 4])
		if hit != null:
			return true
	return false


## Alvo cercado por metal nos 4 eixos (aproximação conservadora: só
## metal conta, pois vidro/pedra são destrutíveis).
static func _target_boxed(def: LevelDefinition, boxes: Array[Rect2]) -> bool:
	var center := def.target.position
	var directions := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	for direction in directions:
		var blocked := false
		# Tipo explícito: `direction` vem de Array sem tipo (Variant)
		# e o `:=` não infere — erro de parse que quebra a cena.
		var ray_end: Vector2 = center + direction * BOXED_RAY_LENGTH
		for i in def.obstacles.size():
			if def.obstacles[i].kind != ObstacleDefinition.KIND_METAL:
				continue
			if boxes[i].size == Vector2.ZERO:
				continue
			if _segment_hits_rect(center, ray_end, boxes[i]):
				blocked = true
				break
		if not blocked:
			return false
	return true
