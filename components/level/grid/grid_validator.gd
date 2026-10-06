class_name GridLevelValidator extends RefCounted
## Validação explícita da fase lógica ANTES de aceitar (rejeita e
## regenera; nunca corrige). Opera sobre a grade + posições físicas
## derivadas dela com os parâmetros reais do jogo (gravidade, boca do
## canhão, corpo do alvo) — sem inventar física paralela: o teste de
## alcance é balística pura com os números de `Cannon`/`ProjectSettings`.

const ERR_NO_FLOOR := "NO_FLOOR"
const ERR_FLOOR_GAP := "FLOOR_GAP"
const ERR_FLOOR_FLAT := "FLOOR_FLAT"
const ERR_NO_CANNON := "NO_CANNON"
const ERR_CANNON_SIDE := "CANNON_SIDE"
const ERR_CANNON_FLOATING := "CANNON_FLOATING"
const ERR_NO_TARGET := "NO_TARGET"
const ERR_TARGET_ON_FLOOR := "TARGET_ON_FLOOR"
const ERR_TARGET_TOO_CLOSE := "TARGET_TOO_CLOSE"
const ERR_OBSTACLE_FLOATING := "OBSTACLE_FLOATING"
const ERR_STRUCTURE_ISOLATED := "STRUCTURE_ISOLATED"
const ERR_TRIVIAL := "TRIVIAL"
const ERR_DIRECT_OPEN := "DIRECT_OPEN"
const ERR_UNREACHABLE := "UNREACHABLE"
const ERR_MUZZLE_BLOCKED := "MUZZLE_BLOCKED"
const ERR_WRONG_MATERIAL := "WRONG_MATERIAL"

const BULLET_RADIUS := 10.0
const MIN_CANNON_TARGET_CELLS := 5


static func validate(grid: GridState) -> Dictionary:
	var errors: Array[String] = []
	_check_floor(grid, errors)
	_check_cannon(grid, errors)
	_check_target(grid, errors)
	_check_connectivity(grid, errors)
	_check_challenge(grid, errors)
	if errors.is_empty():
		_check_ballistics(grid, errors)
	return {"ok": errors.is_empty(), "errors": errors}


## Posição física do canhão: centro da célula, exatamente uma célula
## acima do centro do apoio (pé no topo do Floor, sem offsets mágicos).
static func cannon_world_pos(grid: GridState) -> Vector2:
	var c := grid.find_first(GridState.Cell.CANNON)
	if c.x < 0:
		return Vector2.ZERO
	var support_row := c.y + 1
	while support_row < grid.rows and grid.get_cell(c.x, support_row) != GridState.Cell.FLOOR:
		support_row += 1
	if support_row >= grid.rows:
		return grid.world_pos(c.x, c.y)
	var support := grid.world_pos(c.x, support_row)
	return Vector2(support.x, support.y - GridState.CELL_SIZE)


static func target_world_pos(grid: GridState) -> Vector2:
	var t := grid.find_first(GridState.Cell.TARGET)
	if t.x < 0:
		return Vector2.ZERO
	return grid.world_pos(t.x, t.y)


static func _check_floor(grid: GridState, errors: Array[String]) -> void:
	for col in grid.cols:
		if grid.get_cell(col, grid.rows - 1) != GridState.Cell.FLOOR:
			errors.append(ERR_FLOOR_GAP)
			return
	var relief := 0
	for col in grid.cols:
		if grid.floor_height_at(col) > 0:
			relief += 1
	if relief < 1:
		errors.append(ERR_FLOOR_FLAT)


static func _check_cannon(grid: GridState, errors: Array[String]) -> void:
	var cannons := grid.find_all(GridState.Cell.CANNON)
	if cannons.size() != 1:
		errors.append(ERR_NO_CANNON)
		return
	var c: Vector2i = cannons[0]
	if c.x < 0 or c.x > 3:
		errors.append(ERR_CANNON_SIDE)
	if c.y >= grid.rows - 1:
		errors.append(ERR_CANNON_FLOATING)
		return
	if grid.get_cell(c.x, c.y + 1) != GridState.Cell.FLOOR:
		errors.append(ERR_CANNON_FLOATING)
	# Boca do canhão: as duas células à frente precisam estar livres.
	for dx in [1, 2]:
		var v := grid.get_cell(c.x + dx, c.y)
		if v != GridState.Cell.EMPTY and v != -1:
			errors.append(ERR_MUZZLE_BLOCKED)
			break


static func _check_target(grid: GridState, errors: Array[String]) -> void:
	var targets := grid.find_all(GridState.Cell.TARGET)
	if targets.size() != 1:
		errors.append(ERR_NO_TARGET)
		return
	var t: Vector2i = targets[0]
	if t.y >= grid.rows - 1:
		errors.append(ERR_TARGET_ON_FLOOR)
	var c := grid.find_first(GridState.Cell.CANNON)
	if c.x >= 0 and abs(c.x - t.x) + abs(c.y - t.y) < MIN_CANNON_TARGET_CELLS:
		# Distância de Manhattan mínima canhão↔alvo.
		errors.append(ERR_TARGET_TOO_CLOSE)


static func _connected_to_floor(grid: GridState) -> Dictionary:
	# BFS 4-dir a partir de todas as células de Floor.
	var reached := {}
	var queue: Array[Vector2i] = []
	for row in grid.rows:
		for col in grid.cols:
			var v := grid.get_cell(col, row)
			if v == GridState.Cell.FLOOR:
				var key := Vector2i(col, row)
				reached[key] = true
				queue.append(key)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in dirs:
			var nxt: Vector2i = cur + d
			if not grid.in_bounds(nxt.x, nxt.y):
				continue
			if reached.has(nxt):
				continue
			var v := grid.get_cell(nxt.x, nxt.y)
			if v == GridState.Cell.FLOOR or GridState.is_obstacle(v) or v == GridState.Cell.STRUCTURE:
				reached[nxt] = true
				queue.append(nxt)
	return reached


static func _check_connectivity(grid: GridState, errors: Array[String]) -> void:
	var reached := GridLevelValidator._connected_to_floor(grid)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for row in grid.rows:
		for col in grid.cols:
			var v := grid.get_cell(col, row)
			if GridState.is_obstacle(v):
				if not reached.has(Vector2i(col, row)):
					errors.append(ERR_OBSTACLE_FLOATING)
					return
			elif v == GridState.Cell.STRUCTURE:
				if not reached.has(Vector2i(col, row)):
					errors.append(ERR_STRUCTURE_ISOLATED)
					return
				var touches := false
				for d in dirs:
					var w := grid.get_cell(col + d.x, row + d.y)
					if w == GridState.Cell.FLOOR or GridState.is_obstacle(w) or w == GridState.Cell.STRUCTURE:
						touches = true
						break
				if not touches:
					errors.append(ERR_STRUCTURE_ISOLATED)
					return


## Coerência do desafio: arquétipo precisa dos materiais certos e a
## fase não pode ser trivial (direta aberta quando o arquétipo exige
## bloqueio; mínimo de peças sempre).
static func _check_challenge(grid: GridState, errors: Array[String]) -> void:
	var n_glass := grid.count(GridState.Cell.GLASS)
	var n_stone := grid.count(GridState.Cell.STONE)
	var n_metal := grid.count(GridState.Cell.METAL)
	var total := n_glass + n_stone + n_metal
	if total < 2:
		errors.append(ERR_TRIVIAL)
		return
	match grid.archetype:
		&"break":
			if n_glass < 1:
				errors.append(ERR_WRONG_MATERIAL)
				return
		&"ricochet":
			if n_metal < 1:
				errors.append(ERR_WRONG_MATERIAL)
				return
		&"maze":
			if total < 4:
				errors.append(ERR_TRIVIAL)
				return
		&"vertical":
			var c := grid.find_first(GridState.Cell.CANNON)
			var t := grid.find_first(GridState.Cell.TARGET)
			if c.y + 2 > t.y:
				errors.append(ERR_TRIVIAL)
				return
		&"tower":
			if total < 3:
				errors.append(ERR_TRIVIAL)
				return
		&"mixed":
			var kinds := 0
			if n_glass > 0:
				kinds += 1
			if n_stone > 0:
				kinds += 1
			if n_metal > 0:
				kinds += 1
			if total < 3 or kinds < 2:
				errors.append(ERR_TRIVIAL)
				return
	# Bloqueio da reta canhão→alvo (Bresenham na grade) quando exigido.
	if _needs_blocked_direct(grid.archetype) and not _direct_is_blocked(grid):
		errors.append(ERR_DIRECT_OPEN)


static func _needs_blocked_direct(archetype: StringName) -> bool:
	return archetype == &"break" or archetype == &"ricochet" or archetype == &"maze" or archetype == &"mixed"


## Reta canhão→alvo atravessa alguma célula de obstáculo?
static func _direct_is_blocked(grid: GridState) -> bool:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	if c.x < 0 or t.x < 0:
		return false
	var x0 := c.x
	var y0 := c.y
	var x1 := t.x
	var y1 := t.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while not (x == x1 and y == y1):
		if not (x == x0 and y == y0) and GridState.is_obstacle(grid.get_cell(x, y)):
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return false


## Alcance balístico IGNORANDO obstáculos, com a física real do jogo:
## gravidade do projeto, velocidade base do canhão em cena (2000),
## boca via Cannon.muzzle_state_for e corpo real do alvo dilatado pelo
## raio da bala. Se nem o arco aberto alcança, a fase é impossível.
static func _check_ballistics(grid: GridState, errors: Array[String]) -> void:
	if not _target_reachable_open(grid):
		errors.append(ERR_UNREACHABLE)


static func _target_reachable_open(grid: GridState) -> bool:
	var cannon_pos := GridLevelValidator.cannon_world_pos(grid)
	var target_pos := GridLevelValidator.target_world_pos(grid)
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var body := MaterialRules.target_body_size()
	var rect := Rect2(target_pos - body * 0.5, body).grow(BULLET_RADIUS)
	# Extermínio derivado da FASE (nunca da viewport): fora da área de
	# jogo + margem, ou abaixo do piso (arco que afunda não volta).
	var phase := grid.phase_bounds()
	var kill := phase.grow(300.0)
	var dt := 1.0 / 60.0
	# Amostragem cobre o envelope REAL do canhão (angle_min/max e
	# power_min/max da LevelDefinition): um arco existente aqui é
	# condição necessária p/ solubilidade; a suficiência (desafio com
	# bloqueio) é verificada nas regras de arquétipo, não aqui.
	var angles := [-20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0]
	var powers := [0.3, 0.4, 0.5, 0.7, 0.85, 1.0]
	for angle in angles:
		for power in powers:
			var muzzle := Cannon.muzzle_state_for(cannon_pos, angle)
			var pos: Vector2 = muzzle["origin"]
			var vel: Vector2 = (muzzle["direction"] as Vector2) * 2000.0 * float(power)
			for _step in 240:
				vel += Vector2(0, gravity) * dt
				var nxt := pos + vel * dt
				if _segment_hits_rect(pos, nxt, rect):
					return true
				pos = nxt
				if pos.y > phase.end.y or not kill.has_point(pos):
					break
	return false


static func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(from, to, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false
