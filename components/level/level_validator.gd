class_name LevelValidator extends RefCounted
## Validação estrutural barata, sem física. Duas camadas (docs/plan.md):
## - `validate()`: guardas legados (limites, munição, sobreposição
##   INDEVIDA, miro, alvo). Reprova rápido o geometricamente errado.
## - `validate_structure()`: camada de segurança das regras de
##   docs/Levels.md (floor, apoio do canhão, conectividade, structures
##   com papel, alvo com função, anti-degeneração). Pergunta única:
##   "a composição criada é válida?" — NUNCA conserta; inválido é
##   descartado e outra composição é gerada.
## A solucionabilidade final é do solver (último portão, não desenhista).
## Retorna sempre: {"ok": bool, "errors": Array[String], "warnings": ...}.
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
# Erros estruturais (docs/Levels.md). Nenhum deles tenta corrigir nada.
const ERR_FLOOR_GAP := "FLOOR_GAP"
const ERR_CANNON_FLOATING := "CANNON_FLOATING"
const ERR_CANNON_SIDE := "CANNON_SIDE"
const ERR_FLOOR_NO_ASCENT := "FLOOR_NO_ASCENT"
const ERR_FLOOR_NO_RETURN := "FLOOR_NO_RETURN"
const ERR_OBSTACLE_FLOATING := "OBSTACLE_FLOATING"
const ERR_OBSTACLE_ISOLATED := "OBSTACLE_ISOLATED"
const ERR_STRUCTURE_UNGROUNDED := "STRUCTURE_UNGROUNDED"
const ERR_TARGET_OUT_OF_ROLE := "TARGET_OUT_OF_ROLE"
const ERR_TRIVIAL_COMPOSITION := "TRIVIAL_COMPOSITION"
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
## Tolerâncias [TÉCNICO] da camada estrutural (docs/plan.md): contato
## físico (aresta do grafo), penetração aceita como encosto, pé do
## canhão dentro do tile de apoio. Não são regras de design.
const CONTACT_TOL := 6.0
const OVERLAP_TOL := 6.0
const FOOT_TOL := 8.0
## Zona do canhão (lado esquerdo) e do alvo (lado direito por padrão).
## [TÉCNICO] herdados do validador atual + guides (canhões em x~150).
const CANNON_LEFT_MAX_X := 320.0
const TARGET_RIGHT_MIN_X := 850.0
## Faixa base do piso, herdada dos guides e do builder legado: tiles
## 100x100 centrados em y=670, x de 50 a 1250. [TÉCNICO], não design.
const BASE_Y := 670.0
const BASE_FROM_X := 50.0
const BASE_TO_X := 1250.0
const BASE_TOP := 620.0 # topo da faixa base (670 - 50)


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
			# Composição encosta peças (torre/parede empilhada); só a
			# penetração além de OVERLAP_TOL é sobreposição indevida.
			if _boxes_overlap(boxes[i], boxes[j]):
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


## Sobreposição real entre AABBs: encosto (contato de borda ou
## penetração dentro de OVERLAP_TOL) é construção válida e NÃO erra.
static func _boxes_overlap(a: Rect2, b: Rect2) -> bool:
	var shrink := OVERLAP_TOL * 0.5
	if a.size.x <= shrink * 2.0 or a.size.y <= shrink * 2.0:
		return a.intersects(b)
	if b.size.x <= shrink * 2.0 or b.size.y <= shrink * 2.0:
		return a.intersects(b)
	return a.grow(-shrink).intersects(b.grow(-shrink))


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


## AABB de um tile do Floor (floor_size * scale, sem rotação).
static func floor_aabb(floor: FloorDefinition) -> Rect2:
	var size := MaterialRules.floor_size() * floor.scale
	return Rect2(floor.position - size * 0.5, size)


## AABB de uma Structure (structure_size * scale, 90° troca eixos).
static func structure_aabb(structure: StructureDefinition) -> Rect2:
	var size := MaterialRules.structure_size() * structure.scale
	if absf(wrapf(structure.rotation_degrees, 0.0, 180.0) - 90.0) < 0.01:
		size = Vector2(size.y, size.x)
	return Rect2(structure.position - size * 0.5, size)


## Camada de segurança das regras de docs/Levels.md (docs/plan.md,
## Etapa 3). Só verifica — nunca conserta, nunca reposiciona, nunca
## insere peças. Composição inválida é descartada pelo gerador.
static func validate_structure(def: LevelDefinition) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if def.generator_version != LevelDefinition.GENERATOR_VERSION:
		errors.append(ERR_UNSUPPORTED_VERSION)
		return _result(errors, warnings)

	var floor_boxes: Array[Rect2] = []
	for floor in def.floors:
		var box := floor_aabb(floor)
		floor_boxes.append(box)
		# A faixa base dos guides vai até x=1250 (borda 1300, 20px além
		# de play_bounds): tile vale se o centro está dentro e há
		# interseção — piso pode terminar na borda, nunca fora dela.
		if not def.play_bounds.has_point(box.get_center()) or not box.intersects(def.play_bounds):
			errors.append(ERR_OUT_OF_BOUNDS)

	var obstacle_boxes: Array[Rect2] = []
	for obstacle in def.obstacles:
		if MaterialRules.is_known(obstacle.kind):
			obstacle_boxes.append(obstacle_aabb(obstacle))
		else:
			obstacle_boxes.append(Rect2())

	var structure_boxes: Array[Rect2] = []
	for structure in def.structures:
		if not is_valid_rotation(structure.rotation_degrees):
			errors.append(ERR_INVALID_ROTATION)
		if not is_valid_scale(structure.scale):
			errors.append(ERR_INVALID_SCALE)
		var box := structure_aabb(structure)
		structure_boxes.append(box)
		if not _rect_inside(box, def.play_bounds):
			errors.append(ERR_OUT_OF_BOUNDS)

	# Base contínua: todo ponto da faixa precisa de um tile por perto.
	var x := BASE_FROM_X
	while x <= BASE_TO_X:
		if not _point_covered(Vector2(x, BASE_Y), floor_boxes):
			errors.append(ERR_FLOOR_GAP)
			break
		x += 100.0

	# Canhão: lado esquerdo + pé apoiado num tile.
	if def.cannon_position.x > CANNON_LEFT_MAX_X:
		errors.append(ERR_CANNON_SIDE)
	var foot := Cannon.foot_position(def.cannon_position, def.cannon_scale)
	var support_idx := _support_tile(foot, floor_boxes)
	if support_idx < 0:
		errors.append(ERR_CANNON_FLOATING)

	# Grafo de contato (floors + obstáculos + structures); BFS a partir
	# da fileira base. Aresta = AABBs dilatados se intersectam.
	var adjacency := _contact_graph(floor_boxes, obstacle_boxes, structure_boxes)
	var reached := _bfs_from_base(floor_boxes, adjacency)

	# Subida + retorno: relevo conectado à base; o apoio do canhão
	# elevado precisa estar no componente da base.
	if support_idx >= 0 and foot.y < BASE_TOP - CONTACT_TOL and not reached[support_idx]:
		errors.append(ERR_FLOOR_NO_ASCENT)
	var support_in_disconnected := false
	for i in floor_boxes.size():
		if _is_base_tile(def.floors[i]):
			continue
		if not reached[i]:
			if i == support_idx:
				support_in_disconnected = true
			else:
				errors.append(ERR_FLOOR_NO_RETURN)
				break
	if support_in_disconnected and not errors.has(ERR_FLOOR_NO_ASCENT):
		errors.append(ERR_FLOOR_NO_ASCENT)

	# Obstáculos: sem flutuação (fora do componente da base) nem
	# isolados (grau zero no grafo).
	var obstacle_offset := floor_boxes.size()
	for i in def.obstacles.size():
		if obstacle_boxes[i].size == Vector2.ZERO:
			continue
		var node := obstacle_offset + i
		if adjacency[node].is_empty():
			errors.append(ERR_OBSTACLE_ISOLATED)
		elif not reached[node]:
			errors.append(ERR_OBSTACLE_FLOATING)

	# Structures: cada papel declarado precisa existir geometricamente.
	var by_id := _element_index(def)
	for s in def.structures.size():
		if not _structure_grounded(def, s, floor_boxes, obstacle_boxes, structure_boxes, by_id):
			errors.append(ERR_STRUCTURE_UNGROUNDED)

	# Alvo: zona direita por padrão; exceção só com função declarada.
	if def.target != null:
		if not def.target.exception and def.target.position.x < TARGET_RIGHT_MIN_X:
			errors.append(ERR_TARGET_OUT_OF_ROLE)

	# Anti-degeneração [TÉCNICO]: construção insignificante não é fase
	# (não é "regra dos N" — só barra o vazio/quase-vazio).
	if def.obstacles.is_empty() or (def.obstacles.size() < 2 and def.structures.is_empty()):
		errors.append(ERR_TRIVIAL_COMPOSITION)

	return _result(errors, warnings)


## Ponto coberto por algum tile (dilatado pela tolerância de contato).
static func _point_covered(point: Vector2, boxes: Array[Rect2]) -> bool:
	for box in boxes:
		if box.grow(CONTACT_TOL * 0.5).has_point(point):
			return true
	return false


## Tile de apoio: AABB dilatado contém o pé do canhão.
static func _support_tile(foot: Vector2, floor_boxes: Array[Rect2]) -> int:
	for i in floor_boxes.size():
		if floor_boxes[i].grow(FOOT_TOL).has_point(foot):
			return i
	return -1


static func _is_base_tile(floor: FloorDefinition) -> bool:
	return absf(floor.position.y - BASE_Y) < 1.0


## Grafo de contato: nós = floors ++ obstáculos ++ structures.
static func _contact_graph(floor_boxes: Array[Rect2], obstacle_boxes: Array[Rect2], structure_boxes: Array[Rect2]) -> Array:
	var total := floor_boxes.size() + obstacle_boxes.size() + structure_boxes.size()
	var boxes: Array[Rect2] = []
	boxes.append_array(floor_boxes)
	boxes.append_array(obstacle_boxes)
	boxes.append_array(structure_boxes)
	var adjacency: Array = []
	for i in total:
		adjacency.append([])
	for i in total:
		if boxes[i].size == Vector2.ZERO:
			continue
		for j in range(i + 1, total):
			if boxes[j].size == Vector2.ZERO:
				continue
			var margin := CONTACT_TOL * 0.5
			if boxes[i].grow(margin).intersects(boxes[j].grow(margin)):
				(adjacency[i] as Array).append(j)
				(adjacency[j] as Array).append(i)
	return adjacency


## BFS a partir dos tiles da fileira base. Retorna Array[bool] por nó.
static func _bfs_from_base(floor_boxes: Array[Rect2], adjacency: Array) -> Array:
	var reached: Array = []
	for i in adjacency.size():
		reached.append(false)
	var queue: Array[int] = []
	for i in floor_boxes.size():
		if absf((floor_boxes[i].get_center()).y - BASE_Y) < 1.0:
			reached[i] = true
			queue.append(i)
	while not queue.is_empty():
		var node: int = queue.pop_back()
		for neighbor in adjacency[node]:
			if not reached[neighbor]:
				reached[neighbor] = true
				queue.append(neighbor)
	return reached


## Índice global (no grafo) por id de obstáculo/structure.
static func _element_index(def: LevelDefinition) -> Dictionary:
	var by_id := {}
	var obstacle_offset := def.floors.size()
	for i in def.obstacles.size():
		by_id["obs:" + def.obstacles[i].id] = obstacle_offset + i
	var structure_offset := obstacle_offset + def.obstacles.size()
	for s in def.structures.size():
		by_id["struct:" + def.structures[s].id] = structure_offset + s
	return by_id


## Resolve um link ("obs_01", "struct_02", "floor") para AABBs candidatas.
static func _link_boxes(link: String, def: LevelDefinition, floor_boxes: Array[Rect2], obstacle_boxes: Array[Rect2], structure_boxes: Array[Rect2], by_id: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if link == "floor":
		out.append_array(floor_boxes)
		return out
	var key := "obs:" + link
	if by_id.has(key):
		var box: Rect2 = obstacle_boxes[int(by_id[key]) - def.floors.size()]
		if box.size != Vector2.ZERO:
			out.append(box)
		return out
	key = "struct:" + link
	if by_id.has(key):
		var offset := def.floors.size() + def.obstacles.size()
		var sbox: Rect2 = structure_boxes[int(by_id[key]) - offset]
		if sbox.size != Vector2.ZERO:
			out.append(sbox)
	return out


## Papel declarado existe? beam toca link_a E link_b; support toca
## link_a E alcança o floor. Papel desconhecido ou link inexistente
## também reprova (a declaração precisa ser legível).
static func _structure_grounded(def: LevelDefinition, s: int, floor_boxes: Array[Rect2], obstacle_boxes: Array[Rect2], structure_boxes: Array[Rect2], by_id: Dictionary) -> bool:
	var structure := def.structures[s]
	var box := structure_boxes[s]
	if box.size == Vector2.ZERO:
		return false
	var margin := CONTACT_TOL * 0.5
	if structure.role == StructureDefinition.ROLE_BEAM:
		var boxes_a := _link_boxes(structure.link_a, def, floor_boxes, obstacle_boxes, structure_boxes, by_id)
		var boxes_b := _link_boxes(structure.link_b, def, floor_boxes, obstacle_boxes, structure_boxes, by_id)
		if boxes_a.is_empty() or boxes_b.is_empty():
			return false
		return _touches_any(box, boxes_a, margin) and _touches_any(box, boxes_b, margin)
	if structure.role == StructureDefinition.ROLE_SUPPORT:
		var origins := _link_boxes(structure.link_a, def, floor_boxes, obstacle_boxes, structure_boxes, by_id)
		if origins.is_empty():
			return false
		return _touches_any(box, origins, margin) and _touches_any(box, floor_boxes, margin)
	return false


static func _touches_any(box: Rect2, candidates: Array[Rect2], margin: float) -> bool:
	for candidate in candidates:
		if box.grow(margin).intersects(candidate.grow(margin)):
			return true
	return false
