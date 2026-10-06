class_name GridLevelGenerator extends RefCounted
## Gerador procedural em grade discreta (substitui por completo a lógica
## anterior de composição/arquétipos-places/solver).
##
## Fluxo intencional (nunca `for célula: random()` como estratégia):
## seed -> arquétipo -> dimensões -> grade -> Floor -> Cannon ->
## Target -> desafio -> Structures -> validação -> LevelDefinition.
##
## Aleatoriedade só DENTRO das regras do arquétipo, com um único
## RandomNumberGenerator com seed explícita: mesma
## (seed, versão, fase) => mesma fase. Não instancia Nodes (só dados
## puros); a instanciação é do LevelBuilder existente.

const MAX_CANDIDATES := 30

const ARCH_BREAK := &"break"
const ARCH_RICOCHET := &"ricochet"
const ARCH_MAZE := &"maze"
const ARCH_VERTICAL := &"vertical"
const ARCH_TOWER := &"tower"
const ARCH_MIXED := &"mixed"


## Porta de entrada. Retorna {"def", "grid_ascii", "archetype",
## "candidates", "ms", "fallback_used", "ultimate", "log"}.
static func generate(seed_value: int, level_number: int, cfg: DifficultyConfig = null) -> Dictionary:
	var ammo := 3
	if cfg != null:
		ammo = cfg.ammo
	else:
		ammo = DifficultyTable.get_config(level_number).ammo
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d" % [seed_value, LevelDefinition.GENERATOR_VERSION, level_number])
	var log: Array[String] = []
	var start := Time.get_ticks_msec()
	var tried := 0
	for _attempt in MAX_CANDIDATES:
		tried += 1
		var grid := _build_candidate(rng, level_number)
		var result := GridLevelValidator.validate(grid)
		if not bool(result["ok"]):
			log.append("reject:%s:%s" % [String(grid.archetype), str((result["errors"] as Array).front())])
			continue
		var def := to_def(grid, seed_value, level_number, ammo)
		log.append("accept:%s:%dx%d" % [String(grid.archetype), grid.cols, grid.rows])
		return {
			"def": def, "grid_ascii": grid.to_ascii(),
			"archetype": String(grid.archetype), "candidates": tried,
			"ms": Time.get_ticks_msec() - start, "score": 0.0,
			"fallback_used": false, "ultimate": false, "log": log,
		}
	# Rede final: fase curada mínima (passa no validador, jogável).
	var fallback := _ultimate_grid(level_number)
	var def := to_def(fallback, seed_value, level_number, ammo)
	log.append("ultimate:%s" % String(fallback.archetype))
	return {
		"def": def, "grid_ascii": fallback.to_ascii(),
		"archetype": String(fallback.archetype), "candidates": tried,
		"ms": Time.get_ticks_msec() - start, "score": -1.0,
		"fallback_used": true, "ultimate": true, "log": log,
	}


## Um candidato completo: intenção -> espaço -> peças.
static func _build_candidate(rng: RandomNumberGenerator, level_number: int) -> GridState:
	var archetype := _pick_archetype(rng, level_number)
	var dims := _pick_dimensions(rng, archetype)
	var grid := GridState.new(dims.x, dims.y)
	grid.archetype = archetype
	_build_floor(grid, rng)
	_place_cannon(grid, rng, archetype)
	_place_target(grid, rng, archetype)
	match archetype:
		ARCH_BREAK:
			_build_break(grid, rng)
		ARCH_RICOCHET:
			_build_ricochet(grid, rng)
		ARCH_MAZE:
			_build_maze(grid, rng)
		ARCH_VERTICAL:
			_build_vertical(grid, rng)
		ARCH_TOWER:
			_build_tower(grid, rng)
		_:
			_build_mixed(grid, rng, level_number >= 4)
	_add_cap_structures(grid, rng)
	return grid


## Arquétipo intencional, pesado pela progressão (vidro cedo, metal e
## verticalidade tarde). Nunca sorteio cego de peças: só do conceito.
static func _pick_archetype(rng: RandomNumberGenerator, level_number: int) -> StringName:
	var bag: Array[StringName] = [ARCH_BREAK, ARCH_BREAK, ARCH_TOWER]
	if level_number >= 2:
		bag.append(ARCH_MAZE)
		bag.append(ARCH_MIXED)
	if level_number >= 3:
		bag.append(ARCH_VERTICAL)
	if level_number >= 4:
		bag.append(ARCH_RICOCHET)
	if level_number >= 5:
		bag.append(ARCH_RICOCHET)
		bag.append(ARCH_MIXED)
	return bag[rng.randi_range(0, bag.size() - 1)]


## Dimensões controladas, compatíveis com o desafio (ricochete e
## labirinto pedem área maior; vertical pede altura).
static func _pick_dimensions(rng: RandomNumberGenerator, archetype: StringName) -> Vector2i:
	match archetype:
		ARCH_BREAK:
			return Vector2i(rng.randi_range(12, 13), rng.randi_range(7, 8))
		ARCH_RICOCHET:
			return Vector2i(rng.randi_range(13, 14), rng.randi_range(8, 9))
		ARCH_MAZE:
			return Vector2i(rng.randi_range(13, 14), rng.randi_range(8, 10))
		ARCH_VERTICAL:
			return Vector2i(rng.randi_range(12, 13), rng.randi_range(9, 10))
		ARCH_TOWER:
			return Vector2i(rng.randi_range(12, 14), rng.randi_range(8, 9))
	return Vector2i(rng.randi_range(12, 14), rng.randi_range(7, 10))


## Floor: base contínua na última linha + relevo procedural (2-4
## lombadas de 1-3 colunas x 1-2 de altura, degraus de no máx. 1).
static func _build_floor(grid: GridState, rng: RandomNumberGenerator) -> void:
	for col in grid.cols:
		grid.set_cell(col, grid.rows - 1, GridState.Cell.FLOOR)
	var humps := rng.randi_range(2, 4)
	for _i in humps:
		var w := rng.randi_range(1, 3)
		var h := rng.randi_range(1, 2)
		var start_col := rng.randi_range(4, maxi(4, grid.cols - w - 1))
		for dx in w:
			for dy in h:
				var row := grid.rows - 2 - dy
				if grid.in_bounds(start_col + dx, row) and grid.is_empty(start_col + dx, row):
					grid.set_cell(start_col + dx, row, GridState.Cell.FLOOR)


## Cannon sempre nas 4 primeiras colunas; o Floor SOBE até ele
## (coluna/plataforma), nunca flutuando.
static func _place_cannon(grid: GridState, rng: RandomNumberGenerator, archetype: StringName) -> void:
	var ccol := rng.randi_range(0, 3)
	var crow := grid.rows - 2
	if archetype == ARCH_VERTICAL:
		crow = rng.randi_range(1, 2)
	else:
		var roll := rng.randf()
		if roll < 0.45:
			crow = grid.rows - 2 # baixo, integrado ao plano
		elif roll < 0.8:
			crow = maxi(2, grid.rows - 4) # meia altura
		else:
			crow = rng.randi_range(1, maxi(2, grid.rows - 4)) # alto
	# Sobe o Floor até o canhão (largura 2 quando elevado).
	var width := 1 if crow >= grid.rows - 2 else 2
	for dx in width:
		var col := mini(ccol + dx, grid.cols - 1)
		for row in range(crow + 1, grid.rows):
			if grid.get_cell(col, row) != GridState.Cell.FLOOR:
				grid.set_cell(col, row, GridState.Cell.FLOOR)
	grid.set_cell(ccol, crow, GridState.Cell.CANNON)


## Target no lado direito por padrão; vertical pede alvo baixo.
static func _place_target(grid: GridState, rng: RandomNumberGenerator, archetype: StringName) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var tcol := 0
	var trow := 0
	for _try in 8:
		tcol = rng.randi_range(maxi(5, grid.cols - 4), grid.cols - 1)
		if archetype == ARCH_VERTICAL:
			trow = rng.randi_range(maxi(1, grid.rows - 3), grid.rows - 2)
		else:
			trow = rng.randi_range(0, grid.rows - 2)
		if not grid.is_empty(tcol, trow):
			continue
		var dist: int = absi(tcol - c.x) + absi(trow - c.y)
		if dist >= 5:
			break
	if not grid.is_empty(tcol, trow):
		# Varredura determinística de reserva: primeira livre à direita.
		for row in grid.rows - 1:
			for col in range(grid.cols - 1, 4, -1):
				if grid.is_empty(col, row):
					tcol = col
					trow = row
					break
			if grid.get_cell(tcol, trow) == GridState.Cell.EMPTY:
				break
	grid.set_cell(tcol, trow, GridState.Cell.TARGET)


# ---- Desafios intencionais (materiais com função) ----

static func _put_ob(grid: GridState, col: int, row: int, kind: int) -> bool:
	if not grid.in_bounds(col, row) or not grid.is_empty(col, row):
		return false
	grid.set_cell(col, row, kind)
	return true


## Empilha `height` peças a partir do Floor (base conectada).
static func _stack(grid: GridState, col: int, kinds: Array) -> int:
	var top_row := grid.floor_top_row_at(col)
	if top_row < 0:
		return 0
	var placed := 0
	var row := top_row - 1
	for kind in kinds:
		if not _put_ob(grid, col, row, kind):
			break
		placed += 1
		row -= 1
	return placed


## Barreira de vidro entre canhão e alvo: caminho só abre destruindo.
static func _build_break(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi((c.x + t.x) / 2, c.x + 2, t.x - 1)
	var height := rng.randi_range(2, 3)
	var kinds: Array = []
	for i in height:
		kinds.append(GridState.Cell.GLASS)
	if rng.randf() < 0.5:
		kinds[0] = GridState.Cell.STONE # base com desgaste
	_stack(grid, mid, kinds)
	if rng.randf() < 0.4:
		_stack(grid, mid + 1, [GridState.Cell.GLASS])


## Espelho de metal alto entre canhão e alvo + poste de vidro baixo
## (moldura): a direta morre no metal, o arco por cima resolve.
static func _build_ricochet(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi(t.x - 2, c.x + 2, grid.cols - 1)
	var height := rng.randi_range(3, 4)
	var kinds: Array = []
	for i in height:
		kinds.append(GridState.Cell.METAL)
	kinds[0] = GridState.Cell.STONE # base portante
	_stack(grid, mid, kinds)
	# Poste baixo à esquerda do alvo (moldura, nunca raspão alto).
	var post_col := maxi(c.x + 1, t.x - 4)
	_put_ob(grid, post_col, grid.rows - 2, GridState.Cell.GLASS)


## Corredor: duas colunas de pedra + viga de Structure no topo.
## O projétil precisa descobrir a passagem pelo vão.
static func _build_maze(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var left := clampi((c.x + t.x) / 2 - 1, c.x + 2, grid.cols - 3)
	var h1 := rng.randi_range(2, 3)
	var h2 := rng.randi_range(3, 4)
	var k1: Array = []
	var k2: Array = []
	for i in h1:
		k1.append(GridState.Cell.STONE)
	for i in h2:
		k2.append(GridState.Cell.STONE)
	if rng.randf() < 0.5 and not k1.is_empty():
		k1[k1.size() - 1] = GridState.Cell.GLASS # junta fraca
	_stack(grid, left, k1)
	_stack(grid, left + 2, k2)
	# Viga no topo unindo as colunas (ponte/corredor).
	var top_row := grid.floor_top_row_at(left + 2) - h2
	if grid.in_bounds(left + 1, top_row) and grid.is_empty(left + 1, top_row):
		grid.set_cell(left + 1, top_row, GridState.Cell.STRUCTURE)


## Torre alta no meio: arco cheio por cima + mergulho sobre o alvo.
static func _build_vertical(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi((c.x + t.x) / 2, c.x + 2, t.x - 1)
	var height := rng.randi_range(3, 4)
	var kinds: Array = []
	for i in height:
		kinds.append(GridState.Cell.STONE)
	kinds[kinds.size() - 1] = GridState.Cell.GLASS # topo fraco
	_stack(grid, mid, kinds)


## Fortificação sobre o alvo: torre portante + alas + coroamento.
static func _build_tower(grid: GridState, rng: RandomNumberGenerator) -> void:
	var t := grid.find_first(GridState.Cell.TARGET)
	# Torre portante sob o alvo (pirâmide/zigurate simplificada).
	var under: Array = [GridState.Cell.STONE, GridState.Cell.STONE]
	if rng.randf() < 0.5:
		under.append(GridState.Cell.STONE)
	# Limpa a coluna do alvo e reconstrói como torre.
	for row in range(t.y + 1, grid.rows):
		if grid.get_cell(t.x, row) == GridState.Cell.FLOOR:
			continue
		grid.set_cell(t.x, row, GridState.Cell.EMPTY)
	var cursor := grid.rows - 2
	if grid.floor_height_at(t.x) > 0:
		cursor = grid.floor_top_row_at(t.x) - 1
	for kind in under:
		if cursor <= t.y:
			break
		if grid.is_empty(t.x, cursor):
			grid.set_cell(t.x, cursor, kind)
		cursor -= 1
	# Ala lateral (prédio anexo) + viga de coroamento.
	var wing := t.x - 2 if t.x - 2 > 3 else t.x + 2
	if grid.in_bounds(wing, 0):
		_stack(grid, wing, [GridState.Cell.STONE, GridState.Cell.GLASS])
		var top_a := _top_obstacle_row(grid, t.x)
		var top_b := _top_obstacle_row(grid, wing)
		if top_a >= 0 and top_b >= 0:
			var beam_row := mini(top_a, top_b) - 1
			var step := 1 if wing > t.x else -1
			var cc := t.x + step
			while cc != wing:
				if grid.in_bounds(cc, beam_row) and grid.is_empty(cc, beam_row):
					grid.set_cell(cc, beam_row, GridState.Cell.STRUCTURE)
				cc += step


static func _top_obstacle_row(grid: GridState, col: int) -> int:
	for row in grid.rows:
		if GridState.is_obstacle(grid.get_cell(col, row)):
			return row
	return -1


## Híbrida: barreira destrutível + espelho + anexo em posições distintas.
## Metal só a partir da fase 4 (progressão: vidro/pedra cedo).
static func _build_mixed(grid: GridState, rng: RandomNumberGenerator, allow_metal: bool) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi((c.x + t.x) / 2, c.x + 2, t.x - 1)
	var roll := rng.randf()
	if roll < 0.5 or not allow_metal:
		_build_break(grid, rng)
		if allow_metal:
			_stack(grid, clampi(mid + 3, 0, grid.cols - 1),
					[GridState.Cell.STONE, GridState.Cell.METAL, GridState.Cell.METAL])
		else:
			_stack(grid, clampi(mid + 3, 0, grid.cols - 1),
					[GridState.Cell.STONE, GridState.Cell.GLASS])
	else:
		_build_ricochet(grid, rng)
		_stack(grid, clampi(mid - 2, 0, grid.cols - 1),
				[GridState.Cell.GLASS, GridState.Cell.GLASS])


## Coroamento: vigas de Structure entre topos vizinhos (telhados,
## pontes). Só onde há dois obstáculos próximos com vão livre.
static func _add_cap_structures(grid: GridState, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.25:
		return # nem toda fase precisa de viga
	var tops: Array = []
	for col in grid.cols:
		var r := _top_obstacle_row(grid, col)
		if r >= 0:
			tops.append(Vector2i(col, r))
	for i in range(tops.size()):
		for j in range(i + 1, tops.size()):
			var a: Vector2i = tops[i]
			var b: Vector2i = tops[j]
			if abs(a.x - b.x) > 4 or abs(a.x - b.x) < 2:
				continue
			var beam_row := mini(a.y, b.y) - 1
			if beam_row < 0:
				continue
			var ok := true
			var step := 1 if b.x > a.x else -1
			var cc := a.x + step
			while cc != b.x:
				if not grid.in_bounds(cc, beam_row) or not grid.is_empty(cc, beam_row):
					ok = false
					break
				cc += step
			if ok:
				cc = a.x + step
				while cc != b.x:
					grid.set_cell(cc, beam_row, GridState.Cell.STRUCTURE)
					cc += step
				return


# ---- Conversão lógica -> dados (instanciação fica no LevelBuilder) ----

static func to_def(grid: GridState, seed_value: int, level_number: int, ammo: int) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = ammo
	def.world_bounds = grid.phase_bounds()
	def.cannon_position = GridLevelValidator.cannon_world_pos(grid)
	def.cannon_scale = Cannon.CANNON_SCALE
	# Floors: tile de exatamente CELL_SIZE (500px de arte+colisor).
	for row in grid.rows:
		for col in grid.cols:
			if grid.get_cell(col, row) == GridState.Cell.FLOOR:
				var floor := FloorDefinition.new()
				floor.position = grid.world_pos(col, row)
				floor.scale = GridState.cell_scale_for(Vector2(500, 500))
				def.floors.append(floor)
	# Obstáculos (ids determinísticos em varredura linha-coluna).
	var id_by_cell := {}
	var n := 0
	for row in grid.rows:
		for col in grid.cols:
			var v := grid.get_cell(col, row)
			if not GridState.is_obstacle(v):
				continue
			n += 1
			var ob := ObstacleDefinition.new()
			ob.id = "obs_%02d" % n
			ob.kind = _kind_for(v)
			ob.position = grid.world_pos(col, row)
			# Escala exata da célula a partir da arte/colisor reais
			# (vidro 952x935, pedra 500x500, metal 547x547).
			ob.scale = GridState.cell_scale_for(MaterialRules.base_size(_kind_for(v)))
			ob.group = grid.archetype
			ob.role = _role_for(grid, col, row)
			ob.anchor = _anchor_for(grid, id_by_cell, col, row)
			ob.mechanic = _mechanic_for(v)
			def.obstacles.append(ob)
			id_by_cell[Vector2i(col, row)] = ob.id
	# Structures com links declarados a partir da vizinhança.
	var m := 0
	for row in grid.rows:
		for col in grid.cols:
			if grid.get_cell(col, row) != GridState.Cell.STRUCTURE:
				continue
			m += 1
			var links := _links_for(grid, id_by_cell, col, row)
			var st := StructureDefinition.new()
			st.id = "struct_%02d" % m
			st.position = grid.world_pos(col, row)
			st.rotation_degrees = 90.0 if _is_horizontal_link(grid, col, row) else 0.0
			# Viga de exatamente CELL_SIZE (arte 482x448, rotação preserva).
			st.scale = GridState.cell_scale_for(Vector2(482, 448))
			if (links[0] as String).is_empty() or (links[1] as String).is_empty():
				st.role = StructureDefinition.ROLE_SUPPORT
				st.link_a = links[0] if not (links[0] as String).is_empty() else links[1]
				st.link_b = ""
			else:
				st.role = StructureDefinition.ROLE_BEAM
				st.link_a = links[0]
				st.link_b = links[1]
			def.structures.append(st)
	# Target.
	var t := grid.find_first(GridState.Cell.TARGET)
	def.target = TargetDefinition.new()
	def.target.position = grid.world_pos(t.x, t.y)
	def.target.rotation_degrees = 90.0 if (seed_value + level_number) % 2 == 0 else 0.0
	def.target.role = &"high" if grid.archetype == ARCH_VERTICAL else &"foot"
	def.target.exception = grid.archetype == ARCH_RICOCHET or grid.archetype == ARCH_MAZE
	var tags: Array[StringName] = [grid.archetype, &"grid"]
	def.composition_tags = tags
	return def


static func _kind_for(v: int) -> StringName:
	match v:
		GridState.Cell.GLASS:
			return ObstacleDefinition.KIND_GLASS
		GridState.Cell.METAL:
			return ObstacleDefinition.KIND_METAL
	return ObstacleDefinition.KIND_STONE


static func _mechanic_for(v: int) -> StringName:
	match v:
		GridState.Cell.GLASS:
			return &"breakable"
		GridState.Cell.METAL:
			return &"ricochet"
	return &"wear"


static func _role_for(grid: GridState, col: int, row: int) -> String:
	var below := grid.get_cell(col, row + 1)
	if below == GridState.Cell.FLOOR:
		return "base"
	var v := grid.get_cell(col, row)
	if v == GridState.Cell.METAL:
		return "mirror"
	if GridState.is_obstacle(grid.get_cell(col, row - 1)):
		return "shaft"
	return "top"


static func _anchor_for(grid: GridState, id_by_cell: Dictionary, col: int, row: int) -> String:
	var below_key := Vector2i(col, row + 1)
	if grid.get_cell(col, row + 1) == GridState.Cell.FLOOR:
		return "floor"
	if id_by_cell.has(below_key):
		return String(id_by_cell[below_key])
	return "floor"


static func _links_for(grid: GridState, id_by_cell: Dictionary, col: int, row: int) -> Array:
	var found: Array = []
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d in dirs:
		var key := Vector2i(col + d.x, row + d.y)
		if id_by_cell.has(key):
			found.append(String(id_by_cell[key]))
		elif grid.get_cell(key.x, key.y) == GridState.Cell.FLOOR:
			found.append("floor")
		if found.size() >= 2:
			break
	while found.size() < 2:
		found.append("")
	return found


static func _is_horizontal_link(grid: GridState, col: int, row: int) -> bool:
	var l := grid.get_cell(col - 1, row)
	var r := grid.get_cell(col + 1, row)
	var horiz := (GridState.is_obstacle(l) or l == GridState.Cell.STRUCTURE) or (GridState.is_obstacle(r) or r == GridState.Cell.STRUCTURE)
	var u := grid.get_cell(col, row - 1)
	var d := grid.get_cell(col, row + 1)
	var vert := (GridState.is_obstacle(u) or u == GridState.Cell.STRUCTURE) or (GridState.is_obstacle(d) or d == GridState.Cell.STRUCTURE)
	if horiz and not vert:
		return true
	if vert and not horiz:
		return false
	return abs(grid.world_pos(col - 1, row).x - grid.world_pos(col + 1, row).x) >= abs(grid.world_pos(col, row - 1).y - grid.world_pos(col, row + 1).y)


## Rede final: fase mínima válida (barreira de vidro = desafio de
## destruição; arco aberto existe ignorando obstáculos).
static func _ultimate_grid(_level_number: int) -> GridState:
	var grid := GridState.new(13, 8)
	grid.archetype = ARCH_BREAK
	for col in grid.cols:
		grid.set_cell(col, grid.rows - 1, GridState.Cell.FLOOR)
	# Relevo mínimo (longe da boca do canhão e da reta do desafio).
	for col in [4, 5]:
		grid.set_cell(col, grid.rows - 2, GridState.Cell.FLOOR)
	grid.set_cell(1, grid.rows - 2, GridState.Cell.CANNON)
	grid.set_cell(grid.cols - 2, grid.rows - 3, GridState.Cell.TARGET)
	var mid := 7
	grid.set_cell(mid, grid.rows - 2, GridState.Cell.GLASS)
	grid.set_cell(mid, grid.rows - 3, GridState.Cell.GLASS)
	return grid
