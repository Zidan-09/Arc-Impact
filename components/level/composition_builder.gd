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
const TOWER_DX := 220.0 # torre recuada do alvo (zona de exclusão + folga)
const GATE_GAP := 130.0 # gate–torre: vão que a viga declarada cobre


static func build(rng: RandomNumberGenerator, cfg: DifficultyConfig, seed_value: int, level_number: int) -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = seed_value
	def.level_number = level_number
	def.ammo = cfg.ammo
	def.world_bounds = def.play_bounds
	var comp := Composition.new()

	_build_cannon_floor(def, comp, rng, level_number)
	_build_target(def, comp, rng)
	_build_groups(def, comp, rng, cfg)
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


## Alvo foot: à direita, apoiado no plano, rotação com função.
static func _build_target(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator) -> void:
	var tx := PatternLibrary.pick_target_x(rng)
	def.target = TargetDefinition.new()
	def.target.position = Vector2(tx, PatternLibrary.TARGET_REST_Y)
	def.target.rotation_degrees = PatternLibrary.pick_target_rotation(rng)
	def.target.role = Composition.TARGET_FOOT
	def.target.exception = false
	comp.target_position = def.target.position
	comp.target_rotation = def.target.rotation_degrees
	comp.target_role = Composition.TARGET_FOOT


## Grupos sobre o palco à direita (torre recuada do alvo, gate à
## esquerda da torre). Materiais cabem no orçamento da banda (validate
##_config continua valendo: nada além dos intervalos do cfg).
static func _build_groups(def: LevelDefinition, comp: Composition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> void:
	var tower_x := def.target.position.x - TOWER_DX
	var glass_budget := cfg.glass_count.y - _count_kind(def, ObstacleDefinition.KIND_GLASS)
	var stone_budget := cfg.stone_count.y - _count_kind(def, ObstacleDefinition.KIND_STONE)

	# Gate: barreira sobre a linha do disparo. Vidro nas juntas
	# (quebrar abre caminho); miolo de pedra quando a banda permite
	# desgaste (cobra o 2º impacto).
	var gate_kinds: Array[StringName] = []
	if glass_budget >= 2:
		gate_kinds = [ObstacleDefinition.KIND_GLASS, ObstacleDefinition.KIND_GLASS]
		if stone_budget >= 1 and rng.randf() < 0.7:
			gate_kinds = [ObstacleDefinition.KIND_GLASS, ObstacleDefinition.KIND_STONE,
					ObstacleDefinition.KIND_GLASS]
	elif glass_budget == 1:
		gate_kinds = [ObstacleDefinition.KIND_GLASS]
	else:
		gate_kinds = [ObstacleDefinition.KIND_STONE] if stone_budget >= 1 else []
	var gate_cx := tower_x - GATE_GAP - 100.0 * float(maxi(gate_kinds.size() - 1, 0)) * 0.5 - 50.0
	var gate_group: Dictionary = {"type": Composition.GROUP_GATE, "mechanic": Composition.MECH_BREAKABLE, "pieces": []}
	# Ancorado pelo FIM: a última peça fica a GATE_GAP da torre, onde a
	# viga declarada alcança (vão curto com folga dos dois lados).
	var gx := tower_x - GATE_GAP - 100.0 * float(maxi(gate_kinds.size() - 1, 0))
	var first := true
	for kind in gate_kinds:
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
	if not gate_kinds.is_empty():
		comp.groups.append(gate_group)

	# Tower: moldura de pedra com contato direto (passo = lado da peça).
	# Ganho de vidro no topo quando a banda tem folga (ponto fraco).
	stone_budget = cfg.stone_count.y - _count_kind(def, ObstacleDefinition.KIND_STONE)
	glass_budget = cfg.glass_count.y - _count_kind(def, ObstacleDefinition.KIND_GLASS)
	var height := 0
	if stone_budget >= 2:
		height = 2
	elif stone_budget == 1:
		height = 1
	if height > 0:
		var tower_group: Dictionary = {"type": Composition.GROUP_TOWER, "mechanic": Composition.MECH_FRAME, "pieces": []}
		for i in height:
			_add_ob(def, ObstacleDefinition.KIND_STONE, Vector2(tower_x, GATE_Y_BLOCK - i * 100.0),
					Composition.GROUP_TOWER, "base" if i == 0 else "shaft",
					"floor" if i == 0 else _last_id(def), Composition.MECH_FRAME)
			(tower_group["pieces"] as Array).append(_last_id(def))
		if glass_budget >= 1 and rng.randf() < 0.6:
			_add_ob(def, ObstacleDefinition.KIND_GLASS,
					Vector2(tower_x, GATE_Y_BLOCK - height * 100.0 + 3.0),
					Composition.GROUP_TOWER, "cap", _last_id(def), Composition.MECH_BREAKABLE)
			(tower_group["pieces"] as Array).append(_last_id(def))
			tower_group["mechanic"] = Composition.MECH_BREAKABLE
		comp.groups.append(tower_group)


## Structures com papel: viga entre o fim do gate e a base da torre
## (só existe quando os dois grupos existem — nada de tapa-vão).
static func _build_structures(def: LevelDefinition, comp: Composition) -> void:
	var gate_end := _find_last_role(def, Composition.GROUP_GATE, "leaf")
	if gate_end == null:
		gate_end = _find_last_role(def, Composition.GROUP_GATE, "joint")
	var tower_base := _find_last_role(def, Composition.GROUP_TOWER, "base")
	if gate_end == null or tower_base == null:
		return
	var mid := (gate_end.position + tower_base.position) * 0.5
	var struct := StructureShapes.beam("struct_%02d" % (def.structures.size() + 1),
			gate_end.position, tower_base.position, gate_end.id, tower_base.id)
	def.structures.append(struct)
	comp.structures = [{"role": "beam", "link_a": gate_end.id, "link_b": tower_base.id}]


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
