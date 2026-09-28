class_name CompositionBuilder extends RefCounted
## Monta uma Composition completa combinando padrões (docs/plan.md,
## Etapa 5). ÚNICO lugar onde o RNG toca no desenho. Não posiciona peça
## livre: escolhe intenção do canhão → perfil do floor → função do alvo
## → grupos → structures com papel → materiais por situação/banda.
## Cada peça nasce com grupo/papel/âncora/função; o validador estrutural
## confere depois (reprova sem corrigir) e o solver atesta a jogabilidade.
##
## Vocabulário da Etapa 5 (mínimo): canhão ground/platform/perch(7+),
## floor flat/platform_l/column, alvo foot, grupos gate/tower(+cap),
## structures beam. Ricochete (espelho/fortaleza) chega na Etapa 8.
## Usa SÓ o rng com seed (nunca RNG global). Retorna a LevelDefinition
## pronta para validate() + validate_structure().

const GATE_Y_GLASS := 573.0 # vidro 0.1 apoiado no plano (620 - 46.7)
const GATE_Y_BLOCK := 570.0 # bloco 0.2 apoiado no plano (620 - 50)


static func build(rng: RandomNumberGenerator, cfg: DifficultyConfig, seed_value: int, level_number: int) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = cfg.ammo
	def.world_bounds = def.play_bounds
	var comp := Composition.new()

	_build_cannon_floor(def, comp, rng, level_number)
	if cfg.required_ricochets_min > 0:
		# Bandas 11+: padrão "return" (parede à direita devolve no alvo).
		_build_return_target(def, comp, rng)
		_build_return_groups(def, comp, rng, cfg)
	else:
		_build_target(def, comp, rng, cfg)
		_build_groups(def, comp, rng, cfg)
		if comp.cannon_intent == Composition.CANNON_PERCH:
			_build_low_tower(def, comp, rng, cfg)
	_build_structures(def, comp)

	comp.summarize_tags()
	def.composition_tags = comp.tags
	return def


## Canhão + floor como UMA decisão (o apoio pertence ao desenho).
static func _build_cannon_floor(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, level_number: int) -> void:
	var intent := PatternLibrary.pick_cannon_intent(rng, level_number)
	var cx := PatternLibrary.pick_cannon_x(rng)
	comp.cannon_intent = intent
	def.cannon_scale = Vector2(0.2, 0.2)
	for floor in FloorShapes.base():
		def.floors.append(floor)
	match intent:
		Composition.CANNON_GROUND:
			comp.floor_profile = Composition.FLOOR_FLAT
			def.cannon_position = Vector2(cx, 565.0) # pé em 620, no plano
			comp.cannon_support = "floor"
			comp.shot_intent = "arco direto por cima do gate"
		Composition.CANNON_PLATFORM:
			comp.floor_profile = Composition.FLOOR_PLATFORM_L
			for floor in FloorShapes.platform(cx, 570.0, 2):
				def.floors.append(floor)
			def.cannon_position = Vector2(cx, 465.0) # pé em 520, no patamar
			comp.cannon_support = "floor"
			comp.shot_intent = "arco do patamar por cima do gate"
		_:
			comp.floor_profile = Composition.FLOOR_COLUMN
			var top := PatternLibrary.pick_perch_top(rng)
			for floor in FloorShapes.column(cx, top, 570.0):
				def.floors.append(floor)
			def.cannon_position = Vector2(cx, top - 5.0) # pé no topo
			comp.cannon_support = "floor"
			comp.shot_intent = "mergulho da coluna através do gate"
	comp.cannon_position = def.cannon_position
	comp.cannon_scale = def.cannon_scale


## Alvo: foot (baixo, apoiado no plano) ou high (alto, sobre plataforma
## própria em zigurate, exige arco cheio). High só sem ricochete
## obrigatório (o skip termina no plano); 11+ é sempre foot + skip.
static func _build_target(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> void:
	var role := Composition.TARGET_FOOT
	if cfg.required_ricochets_min == 0:
		role = PatternLibrary.pick_target_role(rng, def.level_number)
	if role == Composition.TARGET_HIGH:
		_build_high_target(def, comp, rng)
		return
	var tx := PatternLibrary.pick_target_x(rng)
	def.target = TargetDefinition.new()
	def.target.position = Vector2(tx, PatternLibrary.TARGET_REST_Y)
	def.target.rotation_degrees = PatternLibrary.pick_target_rotation(rng, role)
	def.target.role = Composition.TARGET_FOOT
	def.target.exception = false
	comp.target_position = def.target.position
	comp.target_rotation = def.target.rotation_degrees
	comp.target_role = Composition.TARGET_FOOT


## Alvo alto sobre zigurate: coluna até a base + patamar + alvo em cima,
## tudo conectado. O desenho é vertical como o Guide2; a queda vem do alto.
static func _build_high_target(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator) -> void:
	var tx := 1050.0 if rng.randf() < 0.5 else 1150.0
	for floor in FloorShapes.column(tx, 430.0, 630.0):
		def.floors.append(floor)
	for floor in FloorShapes.platform(tx, 430.0, 2):
		def.floors.append(floor)
	def.target = TargetDefinition.new()
	def.target.position = Vector2(tx, 340.0) # base 380 = topo do patamar
	def.target.rotation_degrees = PatternLibrary.pick_target_rotation(rng, Composition.TARGET_HIGH)
	def.target.role = Composition.TARGET_HIGH
	def.target.exception = false
	comp.target_position = def.target.position
	comp.target_rotation = def.target.rotation_degrees
	comp.target_role = Composition.TARGET_HIGH


## Grupos sobre o palco à direita. REGRA DE OURO (lição da fase 5):
## na linha do disparo só vidro (atravessa ao destruir); pedra e metal
## REBATEM — sobre a linha viram veneno, fora dela são moldura/espelho.
## Por isso: gate (vidro, na linha) + torre baixa de pedra SÓ com canhão
## alto (linha passa por cima) — nunca muralhando alvo baixo.
## Materiais cabem no orçamento da banda (validate_config continua).
static func _build_groups(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> void:
	var tx := def.target.position.x
	if comp.cannon_intent == Composition.CANNON_GROUND:
		_build_ground_gate(def, comp, rng, cfg, tx)
	else:
		_build_stack_gate(def, comp, rng, cfg, tx)
	# Torre baixa (perch) e skip são orquestrados em build(): skip
	# substitui a torre (ocupariam o mesmo palco).


## Canhão baixo: fileira de 2 vidros sobre a linha (+ miolo de pedra
## quando a banda permite desgaste: 1º tiro racha/rebate, 2º atravessa).
static func _build_ground_gate(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, cfg: DifficultyConfig, tx: float) -> void:
	var glass_budget := cfg.glass_count.y
	var stone_budget := cfg.stone_count.y
	var kinds: Array[StringName] = [ObstacleDefinition.KIND_GLASS, ObstacleDefinition.KIND_GLASS]
	# Miolo de pedra quando a banda permite desgaste — vira fileira de 3
	# para não quebrar o mínimo de vidro. OBRIGATÓRIO se o mínimo do cfg
	# exigir pedra (só o gate a coloca no canhão baixo).
	if stone_budget >= 1 and glass_budget >= 2:
		if cfg.stone_count.x >= 1 or rng.randf() < 0.5:
			kinds = [ObstacleDefinition.KIND_GLASS, ObstacleDefinition.KIND_STONE,
					ObstacleDefinition.KIND_GLASS]
	if kinds.is_empty():
		return
	var slots := [600.0, 700.0, 800.0]
	var gx: float = slots[rng.randi_range(0, slots.size() - 1)]
	# Fileira cabe antes da zona do alvo em qualquer slot (tx >= 1050),
	# com 4px de folga (encosto exato já conta como OVERLAP_TARGET).
	var right_limit := tx - 140.0 - 4.0
	if gx + 100.0 * float(kinds.size() - 1) + 47.6 > right_limit:
		gx = right_limit - 47.6 - 100.0 * float(kinds.size() - 1)
	var gate_group: Dictionary = {"type": Composition.GROUP_GATE, "mechanic": Composition.MECH_BREAKABLE, "pieces": []}
	var first := true
	for kind in kinds:
		var y := GATE_Y_GLASS if kind == ObstacleDefinition.KIND_GLASS else GATE_Y_BLOCK
		var mechanic := Composition.MECH_BREAKABLE if kind == ObstacleDefinition.KIND_GLASS else Composition.MECH_WEAR
		if kind == ObstacleDefinition.KIND_STONE:
			gate_group["mechanic"] = Composition.MECH_WEAR
		_add_ob(def, kind, Vector2(gx, y), Composition.GROUP_GATE,
				"joint" if first else "leaf",
				"floor" if first else _last_id(def), mechanic)
		(gate_group["pieces"] as Array).append(_last_id(def))
		first = false
		gx += 100.0
	comp.groups.append(gate_group)


## Padrão "return" (Etapa 8, bandas 11+): alvo fora da direita
## (desafio especial declarado, docs/Levels.md §4) + torre de retorno à
## direita. O arco passa POR CIMA do alvo, bate na face esquerda da
## torre e volta descendo sobre ele — reflexão com função em eixos
## 0/90, com dezenas de px de margem (face de 100px, alvo de 115px).
## O skip de tampa foi rejeitado: quina de 110px para alvo de 43px era
## fio-de-navalha sistemático (ver Etapa 8 no histórico).
static func _build_return_target(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator) -> void:
	# Slots à direita do centro: distância mínima 500 do canhão com folga
	# (pior caso: canhão (250,465) → (800,580) ≈ 562px).
	var slots := [800.0, 850.0, 900.0]
	var tx: float = slots[rng.randi_range(0, slots.size() - 1)]
	def.target = TargetDefinition.new()
	def.target.position = Vector2(tx, PatternLibrary.TARGET_REST_Y)
	def.target.rotation_degrees = PatternLibrary.pick_target_rotation(rng, Composition.TARGET_EXCEPTION)
	def.target.role = Composition.TARGET_EXCEPTION
	def.target.exception = true
	comp.target_position = def.target.position
	comp.target_rotation = def.target.rotation_degrees
	comp.target_role = Composition.TARGET_EXCEPTION
	comp.shot_intent = "arco por cima do alvo, retorno na torre"


## Torre de retorno + postes de vidro (moldura que cumpre o mínimo de
## vidro da banda). Sem gate: a linha direta atinge o alvo sem reflexão
## e o solver a rejeita pelo mínimo de ricochetes — só o arco com
## retorno passa (solver ciente do mínimo, ver FastLevelGenerator).
static func _build_return_groups(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> void:
	var tx := def.target.position.x
	# Torre a 220px do alvo: perto o bastante para o retorno não
	# amplificar divergências analítico→física, longe da zona (25px+).
	var wall_x := tx + 220.0
	var tower_group: Dictionary = {"type": Composition.GROUP_TOWER,
		"mechanic": Composition.MECH_RICOCHET, "pieces": []}
	var base := _add_ob(def, ObstacleDefinition.KIND_STONE, Vector2(wall_x, GATE_Y_BLOCK),
			Composition.GROUP_TOWER, "base", "floor", Composition.MECH_FRAME)
	(tower_group["pieces"] as Array).append(base.id)
	var shaft := _add_ob(def, ObstacleDefinition.KIND_STONE, Vector2(wall_x, GATE_Y_BLOCK - 100.0),
			Composition.GROUP_TOWER, "shaft", base.id, Composition.MECH_FRAME)
	(tower_group["pieces"] as Array).append(shaft.id)
	var mirror := _add_ob(def, ObstacleDefinition.KIND_METAL, Vector2(wall_x, GATE_Y_BLOCK - 205.0),
			Composition.GROUP_TOWER, "mirror", shaft.id, Composition.MECH_RICOCHET)
	(tower_group["pieces"] as Array).append(mirror.id)
	comp.groups.append(tower_group)
	# Poste de vidro baixo à esquerda do alvo (moldura que cumpre o
	# mínimo de vidro; 12px+ da zona). Baixo (0.05) de propósito: o arco
	# de ida passa bem por cima (poste alto virava raspão sistemático).
	var wall_group: Dictionary = {"type": Composition.GROUP_WALL, "mechanic": Composition.MECH_FRAME, "pieces": []}
	var post := _add_ob(def, ObstacleDefinition.KIND_GLASS, Vector2(tx - 200.0, 596.6),
			Composition.GROUP_WALL, "post", "floor", Composition.MECH_FRAME)
	post.scale = Vector2(0.05, 0.05)
	(wall_group["pieces"] as Array).append(post.id)
	comp.groups.append(wall_group)
## linha descendente (+ miolo de pedra com desgaste). A pilha nasce do
## floor (base conectada) e a linha a atravessa no meio — sólido, não
## raspão. Platform: 2 peças; perch: 3 (linha mais íngreme).
static func _build_stack_gate(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, cfg: DifficultyConfig, tx: float) -> void:
	var glass_budget := cfg.glass_count.y
	var stone_budget := cfg.stone_count.y
	# Altura 3 com folga no vidro (cabe o miolo sem quebrar o mínimo).
	var height := 3 if glass_budget >= 3 else 2
	var kinds: Array[StringName] = []
	for i in height:
		kinds.append(ObstacleDefinition.KIND_GLASS)
	# Pedra NA LINHA: base (platform, linha ~538) ou meio (perch, linha
	# ~463). Sem torre para suprir o mínimo (platform), força quando o
	# mínimo exigir; com torre (perch), só se nem ela bastar (mínimo 2+).
	# Nunca abaixo do mínimo de vidro.
	var need_min := 1 if comp.cannon_intent != Composition.CANNON_PERCH else 2
	var stone_idx := 0 if comp.cannon_intent != Composition.CANNON_PERCH else 1
	if stone_idx >= height:
		stone_idx = height - 1
	if stone_budget >= 1 and height >= 2 and height - 1 >= cfg.glass_count.x:
		if cfg.stone_count.x >= need_min or rng.randf() < 0.5:
			kinds[stone_idx] = ObstacleDefinition.KIND_STONE
	var stack_x := tx - 350.0
	var gate_group: Dictionary = {"type": Composition.GROUP_GATE, "mechanic": Composition.MECH_BREAKABLE, "pieces": []}
	# Empilhamento com cursor exato: cada peça nasce 2px encostada na de
	# baixo (contato garantido para qualquer sequência de materiais).
	var cursor := 620.0 # topo do floor
	for i in kinds.size():
		var kind: StringName = kinds[i]
		var half := 46.7 if kind == ObstacleDefinition.KIND_GLASS else 50.0
		var y := cursor - half
		if kind == ObstacleDefinition.KIND_STONE:
			gate_group["mechanic"] = Composition.MECH_WEAR
		var mechanic := Composition.MECH_BREAKABLE if kind == ObstacleDefinition.KIND_GLASS else Composition.MECH_WEAR
		_add_ob(def, kind, Vector2(stack_x, y), Composition.GROUP_GATE,
				"joint" if i == 0 else ("top" if i == kinds.size() - 1 else "shaft"),
				"floor" if i == 0 else _last_id(def), mechanic)
		(gate_group["pieces"] as Array).append(_last_id(def))
		cursor = y - half + 2.0
	comp.groups.append(gate_group)


## Canhão alto: torre baixa de pedra SOB a linha (moldura, frame) com
## tampa de vidro (ponto fraco opcional, como o miolo do Guide1). A
## linha passa acima da pedra e clipa a tampa — nunca muralha o alvo.
static func _build_low_tower(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> void:
	var tx := def.target.position.x
	var stone_budget := cfg.stone_count.y - _count_kind(def, ObstacleDefinition.KIND_STONE)
	var glass_budget := cfg.glass_count.y - _count_kind(def, ObstacleDefinition.KIND_GLASS)
	if stone_budget < 1:
		return
	var tower_x := tx - 220.0
	var tower_group: Dictionary = {"type": Composition.GROUP_TOWER, "mechanic": Composition.MECH_FRAME, "pieces": []}
	_add_ob(def, ObstacleDefinition.KIND_STONE, Vector2(tower_x, GATE_Y_BLOCK),
			Composition.GROUP_TOWER, "base", "floor", Composition.MECH_FRAME)
	(tower_group["pieces"] as Array).append(_last_id(def))
	if glass_budget >= 1 and rng.randf() < 0.6:
		_add_ob(def, ObstacleDefinition.KIND_GLASS, Vector2(tower_x, GATE_Y_BLOCK - 97.0),
				Composition.GROUP_TOWER, "cap", _last_id(def), Composition.MECH_BREAKABLE)
		(tower_group["pieces"] as Array).append(_last_id(def))
		tower_group["mechanic"] = Composition.MECH_BREAKABLE
	comp.groups.append(tower_group)


## Structures com papel: viga entre a tampa da torre e o topo da pilha
## (coroamento, como o telhado do Guide1). Só existe quando os dois
## grupos existem — nada de tapa-vão.
static func _build_structures(def: LevelDefinition, comp: Composition) -> void:
	var cap := _find_last_role(def, Composition.GROUP_TOWER, "cap")
	var top := _find_last_role(def, Composition.GROUP_GATE, "top")
	if cap == null or top == null:
		return
	var struct := StructureShapes.beam("struct_%02d" % (def.structures.size() + 1),
			top.position, cap.position, top.id, cap.id)
	def.structures.append(struct)
	comp.structures = [{"role": "beam", "link_a": top.id, "link_b": cap.id}]


static func _add_ob(def: LevelDefinition, kind: StringName, pos: Vector2, group: StringName, role: String, anchor: String, mechanic: StringName) -> ObstacleDefinition:
	var ob := ObstacleDefinition.new()
	ob.id = "obs_%02d" % (def.obstacles.size() + 1)
	ob.kind = kind
	ob.position = pos
	ob.scale = PatternLibrary.scale_for(kind)
	ob.group = group
	ob.role = role
	ob.anchor = anchor
	ob.mechanic = mechanic
	def.obstacles.append(ob)
	return ob


static func _last_id(def: LevelDefinition) -> String:
	return def.obstacles[def.obstacles.size() - 1].id


static func _count_kind(def: LevelDefinition, kind: StringName) -> int:
	var n := 0
	for obstacle in def.obstacles:
		if obstacle.kind == kind:
			n += 1
	return n


## Última peça com o papel (o FIM do grupo: extremidade da viga).
static func _find_last_role(def: LevelDefinition, group: StringName, role: String) -> ObstacleDefinition:
	var found: ObstacleDefinition = null
	for obstacle in def.obstacles:
		if obstacle.group == group and obstacle.role == role:
			found = obstacle
	return found
