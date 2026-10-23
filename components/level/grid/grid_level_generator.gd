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
		var result := GridLevelValidator.validate(grid, ammo)
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
	_add_ground_details(grid, rng)
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
## Os intervalos são da resolução-base (128px); a volta para a
## resolução atual preserva a área física da fase para QUALQUER grade.
static func _pick_dimensions(rng: RandomNumberGenerator, archetype: StringName) -> Vector2i:
	var base: Vector2i
	match archetype:
		ARCH_BREAK:
			base = Vector2i(rng.randi_range(12, 13), rng.randi_range(7, 8))
		ARCH_RICOCHET:
			base = Vector2i(rng.randi_range(13, 14), rng.randi_range(8, 9))
		ARCH_MAZE:
			base = Vector2i(rng.randi_range(13, 14), rng.randi_range(8, 10))
		ARCH_VERTICAL:
			base = Vector2i(rng.randi_range(12, 13), rng.randi_range(9, 10))
		ARCH_TOWER:
			base = Vector2i(rng.randi_range(12, 14), rng.randi_range(8, 9))
		_:
			base = Vector2i(rng.randi_range(12, 14), rng.randi_range(7, 10))
	return Vector2i(base.x * GridState.RESOLUTION, base.y * GridState.RESOLUTION)


## Floor: base contínua na última linha + relevo procedural (2-4
## lombadas de 1-3 colunas x 1-2 de altura, degraus de no máx. 1).
## Lombadas são medida FÍSICA da arena: contagem e tamanho vêm em
## células-base e entram na grade já convertidos por `to_cells()`.
static func _build_floor(grid: GridState, rng: RandomNumberGenerator) -> void:
	for col in grid.cols:
		grid.set_cell(col, grid.rows - 1, GridState.Cell.FLOOR)
	var humps := GridState.to_cells(rng.randi_range(2, 4))
	for _i in humps:
		var w := GridState.to_cells(rng.randi_range(1, 3))
		var h := GridState.to_cells(rng.randi_range(1, 2))
		var start_col := rng.randi_range(GridState.to_cells(4), maxi(GridState.to_cells(4), grid.cols - w - 1))
		for dx in w:
			for dy in h:
				var row := grid.rows - 2 - dy
				if grid.in_bounds(start_col + dx, row) and grid.is_empty(start_col + dx, row):
					grid.set_cell(start_col + dx, row, GridState.Cell.FLOOR)


## Cannon sempre nas 4 primeiras colunas-base; o Floor SOBE até ele
## (coluna/plataforma), nunca flutuando.
static func _place_cannon(grid: GridState, rng: RandomNumberGenerator, archetype: StringName) -> void:
	var ccol := rng.randi_range(0, GridState.to_cells(4) - 1)
	var crow := grid.rows - 2
	if archetype == ARCH_VERTICAL:
		crow = rng.randi_range(GridState.to_cells(1), GridState.to_cells(2))
	else:
		var roll := rng.randf()
		if roll < 0.45:
			crow = grid.rows - 2 # baixo, integrado ao plano
		elif roll < 0.8:
			crow = maxi(2, grid.rows - 1 - GridState.to_cells(3)) # meia altura
		else:
			crow = rng.randi_range(GridState.to_cells(1), maxi(2, grid.rows - 1 - GridState.to_cells(3))) # alto
	# Sobe o Floor até o canhão (largura 2-base quando elevado).
	var width := GridState.to_cells(1) if crow >= grid.rows - 2 else GridState.to_cells(2)
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
		tcol = rng.randi_range(maxi(GridState.to_cells(5), grid.cols - GridState.to_cells(4)), grid.cols - 1)
		if archetype == ARCH_VERTICAL:
			trow = rng.randi_range(maxi(1, grid.rows - 1 - GridState.to_cells(2)), grid.rows - 2)
		else:
			trow = rng.randi_range(0, grid.rows - 2)
		if not grid.is_empty(tcol, trow):
			continue
		var dist: int = absi(tcol - c.x) + absi(trow - c.y)
		if dist >= GridState.to_cells(5):
			break
	if not grid.is_empty(tcol, trow):
		# Varredura determinística de reserva: primeira livre à direita.
		for row in grid.rows - 1:
			for col in range(grid.cols - 1, GridState.to_cells(4), -1):
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


## Empilha uma pilha a partir do Floor (base conectada).
## `kinds` é o DESENHO da pilha em células-base (128px): cada camada do
## desenho vira `GridState.RESOLUTION` células atuais. Assim a altura
## física, a proporção de materiais e a ordem das camadas ficam idênticas
## à resolução-base — só a contagem em células muda.
static func _stack(grid: GridState, col: int, kinds: Array) -> int:
	var top_row := grid.floor_top_row_at(col)
	if top_row < 0:
		return 0
	var placed := 0
	var row := top_row - 1
	for kind in _layers(kinds):
		if not _put_ob(grid, col, row, kind):
			break
		placed += 1
		row -= 1
	return placed


## Expande o desenho de uma pilha: cada camada-base ocupa RESOLUTION
## células atuais (mesma altura física da fase).
static func _layers(kinds: Array) -> Array:
	var out: Array = []
	for kind in kinds:
		for _i in GridState.RESOLUTION:
			out.append(kind)
	return out


## Silhueta: várias colunas com ALTURAS DIFERENTES ancoradas no piso de
## cada uma. É a primitiva que quebra o bloco retangulado — degraus,
## paredes escalonadas, dentes, formatos assimétricos. As alturas vêm em
## CÉLULAS-BASE (128px), então a mesma silhueta desenha o mesmo fisco em
## qualquer resolução, só com mais células de precisão.
## `base`/`body`/`cap` definem o material por camada (de baixo p/ cima).
static func _silhouette(grid: GridState, col0: int, heights: Array, base: int, body: int, cap: int = -1) -> void:
	if cap < 0:
		cap = base
	for i in heights.size():
		var h := int(heights[i])
		if h <= 0:
			continue
		var kinds: Array = []
		for layer in h:
			if layer == 0:
				kinds.append(base)
			elif layer == h - 1:
				kinds.append(cap)
			else:
				kinds.append(body)
		_stack(grid, col0 + i, kinds)


## Braço horizontal ancorado no topo de uma pilha existente: cria
## beiradas, telhados e portais CONECTADOS (a base do braço encosta na
## coluna que o originou, então nunca fica flutuante). É a peça que
## fecha a zona superior e faz o arco alto deixar de ser livre.
## Retorna quantas células foram posicionadas.
static func _arm(grid: GridState, col: int, row: int, dir: int, len_base: int, kind: int) -> int:
	var placed := 0
	var c := col
	for _i in GridState.to_cells(len_base):
		c += dir
		if not _put_ob(grid, c, row, kind):
			break
		placed += 1
	return placed


## Alvo protegido: pilar ao lado do alvo + beirada pendurada sobre ele.
## É a peça que fecha o arco alto NA DESCIDA (o arremesso por cima morre
## no teto), mantendo a abertura rasa — o jogador passa a ter de achar o
## vão ou destruir o obstáculo. Ancorada no pilar, nunca flutua.
## Usada nos arquétipos de DESTRUIÇÃO/CORREDOR; os de ricochete ficam
## de fora de propósito (o rebote precisa descer livre até o alvo).
static func _add_target_shelter(grid: GridState, rng: RandomNumberGenerator) -> void:
	var t := grid.find_first(GridState.Cell.TARGET)
	var roof_row := t.y - GridState.to_cells(1)
	if roof_row < 0:
		return
	# Pilar do lado que sobra espaço (preferência: depois do alvo).
	var pillar := t.x + GridState.to_cells(1)
	if pillar >= grid.cols - 1:
		pillar = t.x - GridState.to_cells(1)
	if pillar <= 0 or not grid.in_bounds(pillar, 0):
		return
	var floor_top := grid.floor_top_row_at(pillar)
	if floor_top < 0:
		return
	var h_cells := floor_top - roof_row
	if h_cells < GridState.RESOLUTION:
		return # nada a pendurar: o pilar já chega à beirada
	var h_base := ceili(float(h_cells) / float(GridState.RESOLUTION))
	_silhouette(grid, pillar, [h_base], GridState.Cell.STONE, GridState.Cell.STONE, GridState.Cell.GLASS)
	var toward := -1 if pillar > t.x else 1
	_arm(grid, pillar, roof_row, toward, GridState.to_cells(1), GridState.Cell.STONE)


## Barreira destrutível entre canhão e alvo: caminho só abre destruindo.
## 3 VARIANTES de macroformato (mesma intenção "quebre para passar"):
##   1 MURALHA  - parede alta com silhueta (o arco por cima é fechado).
##   2 DEGRAUS  - parede escalonada + anexo curto (desnível legível).
##   3 BRECHA   - dois postes com vão (o jogador encontra a abertura).
## `height`/gaps são desenho em células-base (cada camada vira
## RESOLUTION células — ver `_stack`); vão livre mínimo é topológico.
static func _build_break(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi((c.x + t.x) / 2, c.x + 2, t.x - 1)
	var variant := rng.randi_range(0, 2)
	match variant:
		0: # MURALHA: silhueta alta, topo irregular, fecha o arco por cima.
			var h := rng.randi_range(4, 6)
			_silhouette(grid, mid, [h, h - 1], GridState.Cell.STONE, GridState.Cell.GLASS, GridState.Cell.GLASS)
		1: # DEGRAUS: altura caindo para a direita + base de desgaste.
			var hl := rng.randi_range(3, 4)
			_silhouette(grid, mid, [hl, hl - 1, maxi(1, hl - 2)], GridState.Cell.STONE, GridState.Cell.GLASS, GridState.Cell.GLASS)
			_stack(grid, mid + GridState.to_cells(3), [GridState.Cell.GLASS])
		_: # JANELA: parede com um vão rasa (o jogador acha a abertura).
			var h := rng.randi_range(3, 5)
			_silhouette(grid, mid, [h, h], GridState.Cell.STONE, GridState.Cell.GLASS, GridState.Cell.GLASS)
			# Vão em células-base, ABAIXO da reta direta: a reta continua
			# bloqueada (o arquétipo exige) mas a abertura rasa existe.
			var win_base := rng.randi_range(1, 2)
			var win_row := mini(t.y + GridState.to_cells(win_base), grid.rows - 2)
			for dx in GridState.to_cells(1):
				for dy in GridState.to_cells(1):
					if GridState.is_obstacle(grid.get_cell(mid + 1 + dx, win_row + dy)):
						grid.set_cell(mid + 1 + dx, win_row + dy, GridState.Cell.EMPTY)
	# Alvo protegido (fecha o arremesso por cima; sobra a abertura rasa).
	if rng.randf() < 0.7:
		_add_target_shelter(grid, rng)


## Espelho de metal + placa de ricochete. A reta direta morre no metal
## e o arco ALTO livre é fechado pela placa no alto — a superfície que
## devolve o projétil para BAIXO (um espelho vertical só rebate para
## trás, então a placa horizontal é a peça que torna o rebote real).
## 3 VARIANTES:  1 ALTO  - espelho alto + placa pendurada.
##              2 LARGO - parede de metal anexa ao piso + placa.
##              3 CANAL - espelho alto + pilar curto = janela rasa.
static func _build_ricochet(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi(t.x - GridState.to_cells(2), c.x + 2, grid.cols - 1)
	var toward := 1 if t.x > mid else -1
	match rng.randi_range(0, 2):
		1: # LARGO: parede larga de metal ancorada no piso.
			var hl := rng.randi_range(3, 5)
			_silhouette(grid, mid, [hl, hl - 1, hl - 2], GridState.Cell.STONE, GridState.Cell.METAL, GridState.Cell.METAL)
		2: # CANAL: espelho + pilar curto, deixando janela rasa entre eles.
			var hm := rng.randi_range(3, 4)
			_silhouette(grid, mid, [hm, hm], GridState.Cell.STONE, GridState.Cell.METAL, GridState.Cell.METAL)
			_silhouette(grid, mid + GridState.to_cells(2), [rng.randi_range(1, 2)],
					GridState.Cell.STONE, GridState.Cell.STONE, GridState.Cell.GLASS)
		_: # ALTO: espelho alto (a parede que mata a reta).
			var h := rng.randi_range(4, 6)
			_silhouette(grid, mid, [h, h], GridState.Cell.STONE, GridState.Cell.METAL, GridState.Cell.METAL)
	# Placa horizontal no topo do espelho, pendurada para o lado do alvo:
	# é ela que rebate o projétil para baixo (e fecha o arco alto livre).
	var top := _top_obstacle_row(grid, mid)
	if top >= 0:
		_arm(grid, mid, top, toward, GridState.to_cells(2), GridState.Cell.METAL)
	# Poste baixo à esquerda do alvo (moldura, nunca raspão alto).
	var post_col := maxi(c.x + 1, t.x - GridState.to_cells(4))
	_put_ob(grid, post_col, grid.rows - 2, GridState.Cell.GLASS)


## Corredor: o projétil precisa descobrir a passagem. 3 VARIANTES de
## macroformato (mesma intenção "ache o vão"):
##   1 CORREDOR - duas colunas + viga de topo (portal).
##   2 COLMEIA  - pilares alternados com janelas em alturas diferentes.
##   3 ESCADA   - degraus ascendentes (o vão fica no alto/lado).
static func _build_maze(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var left := clampi((c.x + t.x) / 2 - 1, c.x + 2, grid.cols - 1 - GridState.to_cells(2))
	var weak := GridState.Cell.GLASS if rng.randf() < 0.5 else GridState.Cell.STONE # junta fraca
	match rng.randi_range(0, 2):
		1: # COLMEIA: pilares de alturas trocadas, janelas em níveis distintos.
			_silhouette(grid, left, [3, 0, 2, 0, 1], GridState.Cell.STONE, GridState.Cell.STONE, weak)
		2: # ESCADA: degraus subindo — a janela boa fica alta e ao lado.
			_silhouette(grid, left, [1, 2, 3, 4], GridState.Cell.STONE, GridState.Cell.STONE, weak)
		_: # CORREDOR: duas colunas + viga de topo (portal).
			_stack(grid, left, _repeat(GridState.Cell.STONE, rng.randi_range(2, 3)))
			var h2 := rng.randi_range(3, 4)
			_stack(grid, left + 2, _repeat(GridState.Cell.STONE, h2))
			# Viga no topo unindo as colunas (ponte/corredor): `h2` é
			# desenho em células-base, então a altura empilhada é to_cells.
			var top_row := grid.floor_top_row_at(left + 2) - GridState.to_cells(h2)
			if grid.in_bounds(left + 1, top_row) and grid.is_empty(left + 1, top_row):
				grid.set_cell(left + 1, top_row, GridState.Cell.STRUCTURE)
	# Alvo protegido: o corredor existe, mas o por-cima está fechado.
	if rng.randf() < 0.7:
		_add_target_shelter(grid, rng)


## Array de `n` cópias do mesmo kind (desenho de pilha em células-base).
static func _repeat(kind: int, n: int) -> Array:
	var out: Array = []
	for _i in n:
		out.append(kind)
	return out


## Torre alta no meio: arco cheio por cima + mergulho sobre o alvo.
static func _build_vertical(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi((c.x + t.x) / 2, c.x + 2, t.x - 1)
	var h := rng.randi_range(3, 5)
	var weak := GridState.Cell.GLASS # topo fraco
	match rng.randi_range(0, 2):
		1: # FENDA: torre partida em dois — o mergulho tem de passar na fenda.
			_silhouette(grid, mid, [h, 0, h - 1], GridState.Cell.STONE, GridState.Cell.STONE, weak)
		2: # RAMPAS: plataformas descendentes em direção ao alvo.
			_silhouette(grid, mid, [h, h - 1, maxi(1, h - 2)], GridState.Cell.STONE, GridState.Cell.STONE, weak)
		_: # TORRE: coluna única no meio (o mergulho clássico).
			var kinds := _repeat(GridState.Cell.STONE, h)
			kinds[kinds.size() - 1] = weak
			_stack(grid, mid, kinds)


## Fortificação sobre o alvo. 3 VARIANTES de macroformato (mesma
## intenção "o alvo está protegido"):
##   1 TORRE    - torre portante + ala + viga de coroamento.
##   2 CASEMATE - torre lateral alta + beirada pendurada sobre o alvo.
##   3 ZIGURATE - ala assimétrica (uma lateral mais alta que a outra).
static func _build_tower(grid: GridState, rng: RandomNumberGenerator) -> void:
	var t := grid.find_first(GridState.Cell.TARGET)
	var variant := rng.randi_range(0, 2)
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
	for kind in _layers(under):
		if cursor <= t.y:
			break
		if grid.is_empty(t.x, cursor):
			grid.set_cell(t.x, cursor, kind)
		cursor -= 1
	# Ala lateral (prédio anexo). A viga de coroamento vai na linha do
	# topo mais BAIXO dos dois (maxi, não mini-1): encosta nos dois
	# lados e nasce conectada, virando telhado/ponte de verdade.
	var wing_gap := GridState.to_cells(2)
	var wing := t.x - wing_gap if t.x - wing_gap > GridState.to_cells(3) else t.x + wing_gap
	if not grid.in_bounds(wing, 0):
		return
	match variant:
		1: # CASEMATE: ala alta + beirada pendurada sobre o alvo.
			var roof_row := maxi(0, t.y - GridState.to_cells(1))
			var h_cells := grid.floor_top_row_at(wing) - roof_row
			if h_cells > 0:
				var h_base := ceili(float(h_cells) / float(GridState.RESOLUTION))
				_silhouette(grid, wing, [maxi(2, h_base)], GridState.Cell.STONE, GridState.Cell.STONE, GridState.Cell.GLASS)
				var toward := 1 if wing < t.x else -1
				_arm(grid, wing, roof_row, toward, GridState.to_cells(1), GridState.Cell.STONE)
				return
			_stack(grid, wing, [GridState.Cell.STONE, GridState.Cell.GLASS])
		2: # ZIGURATE: ala em degraus, um lado mais alto que o outro.
			_silhouette(grid, wing, [rng.randi_range(2, 3), rng.randi_range(1, 2)],
					GridState.Cell.STONE, GridState.Cell.STONE, GridState.Cell.GLASS)
		_:
			_stack(grid, wing, [GridState.Cell.STONE, GridState.Cell.GLASS])
	var top_a := _top_obstacle_row(grid, t.x)
	var top_b := _top_obstacle_row(grid, wing)
	if top_a >= 0 and top_b >= 0:
		var beam_row := maxi(top_a, top_b)
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


## Híbrida: combina duas intenções em posições distintas (barreira +
## espelho + anexo). Metal só a partir da fase 4 (progressão: vidro e
## pedra cedo). A segunda peça entra como SILHUETA (alturas diferentes),
## não como bloco retangulado.
## 3 VARIANTES:   1 PEDRA+METAL - barreira + espelho lateral.
##               2 VIDRO+PEDRA - barreira + monte de desgaste.
##               3 VIDRO+METAL - barreira + parede estreita de metal.
static func _build_mixed(grid: GridState, rng: RandomNumberGenerator, allow_metal: bool) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var t := grid.find_first(GridState.Cell.TARGET)
	var mid := clampi((c.x + t.x) / 2, c.x + 2, t.x - 1)
	var roll := rng.randf()
	if roll < 0.5 or not allow_metal:
		_build_break(grid, rng)
		var col := clampi(mid + GridState.to_cells(3), 0, grid.cols - 1)
		if allow_metal:
			_silhouette(grid, col, [3, 2], GridState.Cell.STONE, GridState.Cell.METAL, GridState.Cell.METAL)
		else:
			_silhouette(grid, col, [2, 1], GridState.Cell.STONE, GridState.Cell.GLASS, GridState.Cell.GLASS)
	else:
		_build_ricochet(grid, rng)
		_silhouette(grid, clampi(mid - GridState.to_cells(2), 0, grid.cols - 1),
				[2, 3], GridState.Cell.STONE, GridState.Cell.GLASS, GridState.Cell.GLASS)


## Coroamento: vigas de Structure ligando topos de obstáculos (telhados,
## pontes, portais). A viga fica EXATAMENTE na linha do topo mais baixo
## dos dois lados — encosta horizontalmente nos dois pilares, então
## nasce CONECTADA (a versão anterior a posicionava 1 célula acima do
## topo mais alto, encostando em nada, e morria como
## STRUCTURE_ISOLATED: por isso a fase nunca tinha teto e o arco alto
## era sempre livre).
## O vão MÁXIMO é medida física (em células-base); o mínimo é
## topológico (precisa sobrar ao menos 1 célula entre os topos).
static func _add_cap_structures(grid: GridState, rng: RandomNumberGenerator) -> void:
	var tops: Array = []
	for col in grid.cols:
		var r := _top_obstacle_row(grid, col)
		if r >= 0:
			tops.append(Vector2i(col, r))
	if tops.size() < 2:
		return
	var t := grid.find_first(GridState.Cell.TARGET)
	# Uma fase pode querer 1 viga (ponte única) ou 2 (teto + portal).
	var want := 1 + (1 if rng.randf() < 0.6 else 0)
	var placed := 0
	var rows_used: Array[int] = []
	for pair in _pairs_by_span(tops):
		if placed >= want:
			break
		if _try_beam(grid, pair[0] as Vector2i, pair[1] as Vector2i, t, rows_used):
			placed += 1


## Pares de topos ordenados pelo vão (mais largo primeiro): a viga
## larga vira teto/ponte de verdade; as seguintes viram portais menores.
static func _pairs_by_span(tops: Array) -> Array:
	var pairs: Array = []
	for i in range(tops.size()):
		for j in range(i + 1, tops.size()):
			pairs.append([tops[i], tops[j]])
	pairs.sort_custom(func(p: Array, q: Array) -> bool:
		return absi((p[0] as Vector2i).x - (p[1] as Vector2i).x) > absi((q[0] as Vector2i).x - (q[1] as Vector2i).x))
	return pairs


## Tenta ligar os topos a e b com uma viga. Exige vão físico livre, a
## linha do topo mais baixo vazia em todo o vão e os dois topos do
## mesmo lado do alvo (nunca encurrala o alvo nem crava viga na linha
## dele). Devolve true quando posicionou.
static func _try_beam(grid: GridState, a: Vector2i, b: Vector2i, t: Vector2i, rows_used: Array[int]) -> bool:
	if absi(a.x - b.x) < 2 or absi(a.x - b.x) > GridState.to_cells(4):
		return false
	var row := maxi(a.y, b.y)
	if row in rows_used:
		return false
	if (a.y > t.y) != (b.y > t.y):
		return false
	var step := 1 if b.x > a.x else -1
	var cc := a.x + step
	while cc != b.x:
		if not grid.in_bounds(cc, row) or not grid.is_empty(cc, row):
			return false
		cc += step
	cc = a.x + step
	while cc != b.x:
		grid.set_cell(cc, row, GridState.Cell.STRUCTURE)
		cc += step
	rows_used.append(row)
	return true


## Detalhe de solo: pilhas curtas ancoradas no Floor espalhadas pela
## base da fase. Existe para a fase GENUÍNAMENTE usar a resolução extra
## (mais elementos, menores, melhor distribuídos — a mesma área física
## comporta mais peças). Entra DEPOIS das vigas de coroamento para não
## alimentar a lógica de viga flutuante; nunca toca a zona da boca do
## canhão e nunca usa Metal (a progressão de material é do arquétipo).
static func _add_ground_details(grid: GridState, rng: RandomNumberGenerator) -> void:
	var c := grid.find_first(GridState.Cell.CANNON)
	var min_col := maxi(GridState.to_cells(4), c.x + 3)
	if min_col > grid.cols - 1:
		return
	var designs: Array = [
		[GridState.Cell.GLASS],
		[GridState.Cell.STONE],
		[GridState.Cell.STONE, GridState.Cell.GLASS],
	]
	for _spot in GridState.to_cells(rng.randi_range(1, 2)):
		var col := rng.randi_range(min_col, grid.cols - 1)
		var top := grid.floor_top_row_at(col) - 1
		if not grid.in_bounds(col, top) or not grid.is_empty(col, top):
			continue # coluna já ocupada (alvo/peça/viga): nada a detalhar
		_stack(grid, col, designs[rng.randi_range(0, designs.size() - 1)])


# ---- Conversão lógica -> dados (instanciação fica no LevelBuilder) ----

static func to_def(grid: GridState, seed_value: int, level_number: int, ammo: int) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = ammo
	def.world_bounds = grid.phase_bounds()
	# Nudge do pé sobre o apoio: ajuste da arte do canhão em px-base,
	# dividido pela resolução para manter o MESMO encaixe relativo.
	def.cannon_position = GridLevelValidator.cannon_world_pos(grid) + Vector2(0, 30.0 / GridState.RESOLUTION)
	# Escala da arte do canhão acompanha a célula (mesma proporção).
	def.cannon_scale = Cannon.CANNON_SCALE / GridState.RESOLUTION
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
## Todos os números aqui são células-base: na resolução 1 o desenho é
## idêntico ao original; na resolução N ele cresce na mesma proporção.
static func _ultimate_grid(_level_number: int) -> GridState:
	var grid := GridState.new(GridState.to_cells(13), GridState.to_cells(8))
	grid.archetype = ARCH_BREAK
	for col in grid.cols:
		grid.set_cell(col, grid.rows - 1, GridState.Cell.FLOOR)
	# Relevo mínimo (longe da boca do canhão e da reta do desafio).
	for col in [GridState.to_cells(4), GridState.to_cells(5)]:
		grid.set_cell(col, grid.rows - 2, GridState.Cell.FLOOR)
	grid.set_cell(GridState.to_cells(1), grid.rows - 2, GridState.Cell.CANNON)
	grid.set_cell(grid.cols - 2, grid.rows - 1 - GridState.to_cells(2), GridState.Cell.TARGET)
	var mid := GridState.to_cells(7)
	# Barreira de 2 células-base de altura sobre o piso.
	for step in GridState.to_cells(2):
		grid.set_cell(mid, grid.rows - 2 - step, GridState.Cell.GLASS)
	return grid
