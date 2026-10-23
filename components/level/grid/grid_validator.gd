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
const ERR_NO_VIABLE_PATH := "NO_VIABLE_PATH"
const ERR_HIGH_ARC_FREE := "HIGH_ARC_FREE"
const ERR_WRONG_BLOCKER := "WRONG_BLOCKER"

const BULLET_RADIUS := 10.0
## Velocidade de saída da bala (Cannon, sem multiplicador de força).
const BULLET_SPEED := 2000.0
## Velocidade retida ao atravessar uma célula: vidro (0.85) e pedra no
## 2º hit (0.85) deixam a bala passar desacelerada — o arco encurta.
const PASS_RETAIN := 0.85
## Ângulo a partir do qual o arco é ALTO: a trajetória de "mire para
## cima e ajuste a força". Abaixo disso, o arco raso é "encontrar a
## abertura" (desafio de mira) — por isso o arco alto é tratado à parte.
const HIGH_ARC_MIN_ANGLE := 45.0
## Limite de arcos ALTOs LIVRES (sem tocar em obstáculo algum) num
## arquétipo que exige bloqueio. 0 = qualquer arco alto livre já é
## rejeitado: ele é a solução de "mire para cima e ajuste a força" que
## homogeneiza as fases. A fase precisa fechar o por-cima e obrigar o
## jogador a encontrar a abertura, destruir ou rebater.
const MAX_FREE_HIGH_ARCS := 0
## Distância mínima canhão↔alvo (Manhattan) EM CÉLULAS-BASE de 128px;
## convertida na hora do teste por `GridState.to_cells()` para valer a
## mesma distância física em qualquer resolução.
const MIN_CANNON_TARGET_CELLS := 5


static func validate(grid: GridState, ammo: int = 3) -> Dictionary:
	var errors: Array[String] = []
	_check_floor(grid, errors)
	_check_cannon(grid, errors)
	_check_target(grid, errors)
	_check_connectivity(grid, errors)
	_check_challenge(grid, errors)
	if errors.is_empty():
		_check_ballistics(grid, ammo, errors)
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
	# Piso precisa de relevo em pelo menos 1 célula-base de largura.
	if relief < GridState.to_cells(1):
		errors.append(ERR_FLOOR_FLAT)


static func _check_cannon(grid: GridState, errors: Array[String]) -> void:
	var cannons := grid.find_all(GridState.Cell.CANNON)
	if cannons.size() != 1:
		errors.append(ERR_NO_CANNON)
		return
	var c: Vector2i = cannons[0]
	# Zona do canhão: 4 células-base a partir da borda esquerda.
	if c.x < 0 or c.x > GridState.to_cells(4) - 1:
		errors.append(ERR_CANNON_SIDE)
	if c.y >= grid.rows - 1:
		errors.append(ERR_CANNON_FLOATING)
		return
	if grid.get_cell(c.x, c.y + 1) != GridState.Cell.FLOOR:
		errors.append(ERR_CANNON_FLOATING)
	# Boca do canhão: as duas células à frente precisam estar livres.
	# Topológico (em volta da própria boca, cuja arte encolhe com a
	# célula), não medida física de arena — não escala com RESOLUTION.
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
	if c.x >= 0 and abs(c.x - t.x) + abs(c.y - t.y) < GridState.to_cells(MIN_CANNON_TARGET_CELLS):
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
## Limiares de CONTAGEM (peças) e de ALTURA são em unidades-base de
## 128px, convertidos por `GridState.to_cells()`; presença de material
## (>=1 peça de um kind) e diversidade de kinds são topológicas e ficam
## como estão.
static func _check_challenge(grid: GridState, errors: Array[String]) -> void:
	var n_glass := grid.count(GridState.Cell.GLASS)
	var n_stone := grid.count(GridState.Cell.STONE)
	var n_metal := grid.count(GridState.Cell.METAL)
	var total := n_glass + n_stone + n_metal
	if total < GridState.to_cells(2):
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
			if total < GridState.to_cells(4):
				errors.append(ERR_TRIVIAL)
				return
		&"vertical":
			var c := grid.find_first(GridState.Cell.CANNON)
			var t := grid.find_first(GridState.Cell.TARGET)
			if c.y + GridState.to_cells(2) > t.y:
				errors.append(ERR_TRIVIAL)
				return
		&"tower":
			if total < GridState.to_cells(3):
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
			if total < GridState.to_cells(3) or kinds < 2:
				errors.append(ERR_TRIVIAL)
				return
	# Bloqueio da reta canhão→alvo (Bresenham na grade) quando exigido.
	var direct := _direct_kinds(grid)
	if _needs_blocked_direct(grid.archetype) and direct.is_empty():
		errors.append(ERR_DIRECT_OPEN)
		return
	# O MATERIAL do bloqueio precisa ser o da intenção do arquétipo:
	# ricochete com parede de vidro/pedra não é ricochete (o jogador só
	# destrói e passa); break com metal não abre destruindo.
	match grid.archetype:
		&"ricochet":
			if GridState.Cell.METAL not in direct:
				errors.append(ERR_WRONG_BLOCKER)
		&"break":
			if GridState.Cell.METAL in direct:
				errors.append(ERR_WRONG_BLOCKER)


static func _needs_blocked_direct(archetype: StringName) -> bool:
	return archetype == &"break" or archetype == &"ricochet" or archetype == &"maze" or archetype == &"mixed"


## Reta canhão→alvo atravessa alguma célula de obstáculo?
static func _direct_is_blocked(grid: GridState) -> bool:
	return not _direct_kinds(grid).is_empty()


## Materiais distintos que cruzam a reta canhão→alvo (Bresenham na
## grade). É o bloqueio que o arquétipo enxerga: metal => parede
## impossível de atravessar (só ricochete); destrutível (vidro/pedra)
## => caminho que abre destruindo. Metal numa fase de "quebra" seria
## outra coisa — por isso o material do bloqueio importa.
static func _direct_kinds(grid: GridState) -> Array[int]:
	var out: Array[int] = []
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	if c.x < 0 or t.x < 0:
		return out
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
			var v := grid.get_cell(x, y)
			if v not in out:
				out.append(v)
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return out


## Solubilidade e qualidade do desafio com a física real sobre a GRADE.
## O arco que IGNORA obstáculos (regra antiga) não basta: ele existe
## sempre que o jogador pode mirar para cima e ajustar a força, e é
## exatamente isso que homogeneiza as fases. As regras daqui pedem um
## caminho que caiba na MUNIÇÃO e, nos arquétipos de bloqueio, que o
## arco alto LIVRE esteja fechado.
static func _check_ballistics(grid: GridState, ammo: int, errors: Array[String]) -> void:
	var arcs := sample_arcs(grid, ammo)
	if int(arcs["reachable"]) == 0:
		errors.append(ERR_UNREACHABLE)
		return
	# Ricochete fica de fora do teste de munição: o metal mata as
	# trajetórias que chegariam (o arquétipo exige bloqueio) e o rebote
	# que resolve é física do motor, não da amostragem.
	if grid.archetype != &"ricochet" and int(arcs["viable"]) == 0:
		errors.append(ERR_NO_VIABLE_PATH)
		return
	# "Mire para cima e ajuste a força": nos arquétipos que exigem
	# bloqueio da reta direta, nenhum arco alto pode chegar LIVRE.
	if _needs_blocked_direct(grid.archetype) and int(arcs["high_clean"]) > MAX_FREE_HIGH_ARCS:
		errors.append(ERR_HIGH_ARC_FREE)


## Afina uma malha de amostras (ângulos/potências) em RESOLUTION
## intervalos entre vizinhos consecutivos. Em RESOLUTION = 1 devolve a
## lista intacta; em N, o passo cai para 1/N — a mesma fidelidade de
## captura do alvo, que passa a ocupar 1/N da célula.
static func _refine(values: Array) -> Array:
	var res := GridState.RESOLUTION
	if res <= 1 or values.size() < 2:
		return values
	var out: Array = []
	for i in range(values.size() - 1):
		var a := float(values[i])
		var b := float(values[i + 1])
		for step in res:
			out.append(lerpf(a, b, float(step) / float(res)))
	out.append(float(values[values.size() - 1]))
	return out


static func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(from, to, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false


## Amostra o envelope do canhão sobre a GRADE (não só a geometria) e
## classifica cada arco pelo que ele ENCONTRA no caminho. Física real do
## jogo, sem simulação paralela: gravidade do projeto, boca via
## Cannon.muzzle_state_for, corpo do alvo dilatado pelo raio da bala,
## desaceleração de travessia e piso que segura a bala.
##
## Regras de munição usadas (as mesmas do jogo):
##  - vidro: 1 hit e quebra => atravessa NO MESMO disparo, x0.85;
##  - pedra: 1º hit racha e mata o disparo, 2º atravessa => cada célula
##    de pedra no caminho custa 2 tiros;
##  - metal: indestrutível => nenhum disparo passa (só ricochete).
##
## Métricas:
##  - reachable: arcos que chegam ao alvo pagando a travessia;
##  - viable: reachable sem metal e cabendo na munição (solucionável
##    de verdade, não só geometricamente);
##  - clean: viable sem pedra e sem vidro (tiro livre);
##  - high_*: idem contando SÓ arcos altos (>= HIGH_ARC_MIN_ANGLE) — a
##    solução universal de "mirar para cima e achar a força";
##  - direct: materiais que cruzam a reta direta.
static func sample_arcs(grid: GridState, ammo: int) -> Dictionary:
	var total := 0
	var reachable := 0
	var viable := 0
	var clean := 0
	var high_total := 0
	var high_reachable := 0
	var high_viable := 0
	var high_clean := 0
	var viable_glass := 0
	var viable_stone := 0
	var cannon_pos := GridLevelValidator.cannon_world_pos(grid)
	var target_pos := GridLevelValidator.target_world_pos(grid)
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var body := MaterialRules.target_body_size()
	var rect := Rect2(target_pos - body * 0.5, body).grow(BULLET_RADIUS)
	var phase := grid.phase_bounds()
	var kill := phase.grow(300.0)
	var dt := 1.0 / 60.0
	# Malha densa só em cima de ~45°: é ali que existe (ou não) o "arco
	# alto livre" — banda estreita de força que a malha grossa atravessa e
	# deixa a fase passar. Abaixo disso a trajetória é rasa por
	# construção, então a faixa baixa fica esparsa (a abertura rasada é
	# larga; não precisa de tantas amostras para encontrá-la).
	var angles := _refine([-15.0, 0.0, 15.0, 30.0, 45.0, 55.0, 65.0, 75.0])
	var powers_low := _refine([0.35, 0.5, 0.7, 0.9])
	var powers_high := _refine([0.55, 0.7, 0.8, 0.9, 1.0])
	for angle in angles:
		var high := float(angle) >= HIGH_ARC_MIN_ANGLE
		var powers := powers_high if high else powers_low
		for power in powers:
			total += 1
			if high:
				high_total += 1
			var muzzle := Cannon.muzzle_state_for(cannon_pos, angle)
			var pos: Vector2 = muzzle["origin"]
			var vel: Vector2 = (muzzle["direction"] as Vector2) * BULLET_SPEED * float(power)
			var stones := 0
			var glass := 0
			var metal := false
			var passed := {}
			var hit := false
			# Teto de passos = alcance máximo do envelope (o arco já caiu
			# bem antes disso); 240 era folga que só custava tempo.
			for _step in 140:
				vel += Vector2(0, gravity) * dt
				var nxt := pos + vel * dt
				if _segment_hits_rect(pos, nxt, rect):
					hit = true
					break
				pos = nxt
				if pos.y > phase.end.y or not kill.has_point(pos):
					break
				var cell := grid.cell_of(pos)
				if cell.x < 0:
					break
				var v := grid.get_cell(cell.x, cell.y)
				if v == GridState.Cell.FLOOR:
					break # bala crava no chão: este arco não volta
				if GridState.is_obstacle(v) and not passed.has(cell):
					passed[cell] = true
					vel *= PASS_RETAIN
					if v == GridState.Cell.STONE:
						stones += 1
					elif v == GridState.Cell.METAL:
						metal = true
					else:
						glass += 1
			if not hit:
				continue
			reachable += 1
			if high:
				high_reachable += 1
			if metal or 1 + stones > ammo:
				continue
			viable += 1
			if high:
				high_viable += 1
			if glass > 0:
				viable_glass += 1
			elif stones > 0:
				viable_stone += 1
			else:
				clean += 1
				if high:
					high_clean += 1
	return {
		"total": total, "reachable": reachable, "viable": viable, "clean": clean,
		"high_total": high_total, "high_reachable": high_reachable,
		"high_viable": high_viable, "high_clean": high_clean,
		"viable_glass": viable_glass, "viable_stone": viable_stone,
		"direct": _direct_kinds(grid),
	}
