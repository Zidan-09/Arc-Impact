extends SceneTree
## Teste do LevelValidator da Etapa 3 (DoD: casos inválidos com o código
## correto + 200 defs válidas aprovadas).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/level_validator_test.gd
## Saída: "LEVEL_VALIDATOR_TEST: PASS" (exit 0) ou FAIL (exit 1).
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.


func _init() -> void:
	var failures: int = 0
	failures += _check_valid_base()
	failures += _check_out_of_bounds()
	failures += _check_overlap_obstacle()
	failures += _check_overlap_cannon()
	failures += _check_overlap_target()
	failures += _check_target_too_close()
	failures += _check_target_boxed()
	failures += _check_integrity()
	failures += _check_missing_target()
	failures += _check_config()
	failures += _check_bulk_valid()
	failures += _check_structure_valid()
	failures += _check_structure_errors()
	failures += _check_contact_allowed()
	failures += _check_guide1_support()
	if failures == 0:
		print("LEVEL_VALIDATOR_TEST: PASS")
	else:
		printerr("LEVEL_VALIDATOR_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


## Base válida verificada à mão (AABBs sem toque, alvo longe, tudo dentro).
func _base_def() -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = 7
	def.level_number = 5
	def.ammo = 3
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1000, 200)
	var glass := ObstacleDefinition.new()
	glass.id = "obs_01"
	glass.kind = ObstacleDefinition.KIND_GLASS
	glass.position = Vector2(600, 400)
	glass.scale = Vector2(0.1, 0.1)
	def.obstacles.append(glass)
	var stone := ObstacleDefinition.new()
	stone.id = "obs_02"
	stone.kind = ObstacleDefinition.KIND_STONE
	stone.position = Vector2(800, 300)
	def.obstacles.append(stone)
	return def


func _has_code(result: Dictionary, code: String) -> bool:
	return code in result["errors"]


func _check_valid_base() -> int:
	var result := LevelValidator.validate(_base_def())
	if not result["ok"]:
		return _fail("base válida reprovada: %s" % str(result["errors"]))
	return 0


func _check_out_of_bounds() -> int:
	var def := _base_def()
	def.obstacles[1].position = Vector2(1250, 700) # AABB passa de 1280
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_OUT_OF_BOUNDS):
		return _fail("fora de limites não gerou OUT_OF_BOUNDS")
	return 0


func _check_overlap_obstacle() -> int:
	var def := _base_def()
	def.obstacles[1].position = Vector2(650, 400) # invade o vidro
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_OVERLAP_OBSTACLE):
		return _fail("sobreposição não gerou OVERLAP_OBSTACLE")
	return 0


func _check_overlap_cannon() -> int:
	var def := _base_def()
	def.obstacles[1].position = Vector2(300, 523) # a 72px do canhão
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_OVERLAP_CANNON):
		return _fail("obstáculo no canhão não gerou OVERLAP_CANNON")
	return 0


func _check_overlap_target() -> int:
	var def := _base_def()
	def.obstacles[0].position = Vector2(1000, 200) # em cima do alvo
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_OVERLAP_TARGET):
		return _fail("obstáculo no alvo não gerou OVERLAP_TARGET")
	return 0


func _check_target_too_close() -> int:
	var def := _base_def()
	def.obstacles.clear()
	def.target.position = Vector2(500, 500) # a ~328px do canhão
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_TARGET_TOO_CLOSE):
		return _fail("alvo colado não gerou TARGET_TOO_CLOSE")
	return 0


func _check_target_boxed() -> int:
	# 4 metais a 210px do alvo: bloqueiam os 4 raios sem tocar a zona de 100px.
	var def := _base_def()
	def.obstacles.clear()
	def.target.position = Vector2(1000, 360)
	var spots := [Vector2(1000, 150), Vector2(1000, 570), Vector2(790, 360), Vector2(1210, 360)]
	for i in spots.size():
		var metal := ObstacleDefinition.new()
		metal.id = "metal_%d" % i
		metal.kind = ObstacleDefinition.KIND_METAL
		metal.position = spots[i]
		def.obstacles.append(metal)
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_TARGET_BOXED):
		return _fail("alvo cercado não gerou TARGET_BOXED: %s" % str(result["errors"]))
	return 0


func _check_integrity() -> int:
	var failures: int = 0
	var def := _base_def()
	def.obstacles[0].kind = &"adamantium"
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_INVALID_KIND):
		failures += _fail("kind desconhecido não gerou INVALID_KIND")
	def = _base_def()
	def.obstacles[1].rotation_degrees = 45.0
	result = LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_INVALID_ROTATION):
		failures += _fail("rotação 45 não gerou INVALID_ROTATION")
	def = _base_def()
	def.obstacles[0].scale = Vector2(2, 2)
	result = LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_INVALID_SCALE):
		failures += _fail("escala 2 não gerou INVALID_SCALE")
	def = _base_def()
	def.ammo = 0
	result = LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_INVALID_AMMO):
		failures += _fail("ammo 0 não gerou INVALID_AMMO")
	def = _base_def()
	def.generator_version = 999
	result = LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_UNSUPPORTED_VERSION):
		failures += _fail("versão 999 não gerou UNSUPPORTED_VERSION")
	return failures


func _check_missing_target() -> int:
	var def := _base_def()
	def.target = null
	var result := LevelValidator.validate(def)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_MISSING_TARGET):
		return _fail("alvo ausente não gerou MISSING_TARGET")
	return 0


func _check_config() -> int:
	var cfg := DifficultyTable.get_config(12) # ammo 3, vidro/pedra/metal 1-3
	var def := LevelDefinition.new()
	def.ammo = 3
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1100, 150)
	var specs := [
		["g1", ObstacleDefinition.KIND_GLASS, Vector2(500, 150), Vector2(0.1, 0.1)],
		["g2", ObstacleDefinition.KIND_GLASS, Vector2(630, 150), Vector2(0.1, 0.1)],
		["s1", ObstacleDefinition.KIND_STONE, Vector2(750, 450), Vector2(0.2, 0.2)],
		["m1", ObstacleDefinition.KIND_METAL, Vector2(950, 550), Vector2(0.2, 0.2)],
	]
	for spec in specs:
		var ob := ObstacleDefinition.new()
		ob.id = spec[0]
		ob.kind = spec[1]
		ob.position = spec[2]
		ob.scale = spec[3]
		def.obstacles.append(ob)
	if not LevelValidator.validate(def)["ok"]:
		return _fail("def do teste de config reprovada no validate()")
	var result := LevelValidator.validate_config(def, cfg)
	if not result["ok"]:
		return _fail("config compatível reprovada: %s" % str(result["errors"]))
	def.ammo = 2
	result = LevelValidator.validate_config(def, cfg)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_CONFIG_AMMO_MISMATCH):
		return _fail("ammo divergente não gerou CONFIG_AMMO_MISMATCH")
	def.ammo = 3
	def.obstacles.pop_back() # remove o metal: 0 < mínimo 1
	result = LevelValidator.validate_config(def, cfg)
	if result["ok"] or not _has_code(result, LevelValidator.ERR_CONFIG_COUNT_OUT_OF_RANGE):
		return _fail("contagem fora da faixa não gerou CONFIG_COUNT_OUT_OF_RANGE")
	return 0


func _check_bulk_valid() -> int:
	# 200 defs determinísticas em grade espaçada: todas devem passar.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# Grade espaçada fora do corredor do muzzle (canhão + (280,-60)):
	# (450,420) continha o fim do corredor e gerava MUZZLE_BLOCKED.
	var cells := [Vector2(450, 120), Vector2(600, 120), Vector2(750, 120),
		Vector2(450, 270), Vector2(600, 270), Vector2(750, 270),
		Vector2(900, 420), Vector2(600, 420), Vector2(750, 420),
		Vector2(450, 570), Vector2(600, 570), Vector2(750, 570)]
	for i in 200:
		var def := LevelDefinition.new()
		def.seed = i
		def.level_number = 5
		def.ammo = 3
		def.target = TargetDefinition.new()
		def.target.position = Vector2(1100, 150)
		var first := rng.randi_range(0, cells.size() - 1)
		var second := rng.randi_range(0, cells.size() - 2)
		if second >= first:
			second += 1
		var picks := [first, second]
		for k in 2:
			var ob := ObstacleDefinition.new()
			ob.id = "obs_%d" % k
			ob.kind = ObstacleDefinition.KIND_METAL if (i + k) % 2 == 0 else ObstacleDefinition.KIND_STONE
			ob.position = cells[picks[k]]
			ob.rotation_degrees = 90.0 if rng.randi_range(0, 1) == 1 else 0.0
			def.obstacles.append(ob)
		var result := LevelValidator.validate(def)
		if not result["ok"]:
			return _fail("def bulk %d reprovada: %s" % [i, str(result["errors"])])
	return 0


func _fail(message: String) -> int:
	printerr("  [validator] " + message)
	return 1


## Composição válida (Etapa 3): canhão no plano + base contínua + gate
## de 2 vidros encostados no floor + alvo à direita com função.
## Passa em validate() E validate_structure().
func _struct_def() -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = 7
	def.level_number = 5
	def.ammo = 3
	def.cannon_position = Vector2(200, 565)
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1150, 300)
	def.target.role = Composition.TARGET_FOOT
	var x := 50.0
	while x <= 1250.0:
		var floor := FloorDefinition.new()
		floor.position = Vector2(x, 670)
		def.floors.append(floor)
		x += 100.0
	for i in 2:
		var glass := ObstacleDefinition.new()
		glass.id = "obs_%02d" % (i + 1)
		glass.kind = ObstacleDefinition.KIND_GLASS
		glass.position = Vector2(950 + i * 100, 573)
		glass.scale = Vector2(0.1, 0.1)
		glass.group = Composition.GROUP_GATE
		glass.role = "joint" if i == 0 else "leaf"
		glass.anchor = "floor" if i == 0 else "obs_01"
		glass.mechanic = Composition.MECH_BREAKABLE
		def.obstacles.append(glass)
	return def


func _check_structure_valid() -> int:
	var def := _struct_def()
	var legacy := LevelValidator.validate(def)
	if not legacy["ok"]:
		return _fail("composição válida reprovada no validate(): %s" % str(legacy["errors"]))
	var result := LevelValidator.validate_structure(def)
	if not result["ok"]:
		return _fail("composição válida reprovada: %s" % str(result["errors"]))
	return 0


## Cada código estrutural com fixture mínima (a validação reprova sem
## consertar: cada caso deve conter EXATAMENTE o código esperado além
## dos inevitáveis — o teste exige a presença, não a exclusividade,
## exceto onde anotado).
func _check_structure_errors() -> int:
	var failures := 0
	# FLOOR_GAP: base sem o tile x=650.
	var def := _struct_def()
	for i in def.floors.size():
		if def.floors[i].position.x == 650.0:
			def.floors.remove_at(i)
			break
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_FLOOR_GAP):
		failures += _fail("base com vão não gerou FLOOR_GAP")
	# CANNON_FLOATING: canhão alto sem apoio.
	def = _struct_def()
	def.cannon_position = Vector2(200, 300)
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_CANNON_FLOATING):
		failures += _fail("canhão sem apoio não gerou CANNON_FLOATING")
	# CANNON_SIDE: canhão fora da esquerda.
	def = _struct_def()
	def.cannon_position = Vector2(640, 565)
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_CANNON_SIDE):
		failures += _fail("canhão à direita não gerou CANNON_SIDE")
	# FLOOR_NO_ASCENT: plataforma isolada (apoio fora do componente).
	# Plataforma em y=470: contém o pé mas não encosta na base (vão
	# de 100px até o topo 620) nem em nada — apoio desancorado.
	def = _struct_def()
	def.cannon_position = Vector2(200, 465)
	var platform := FloorDefinition.new()
	platform.position = Vector2(200, 470)
	def.floors.append(platform)
	var result := LevelValidator.validate_structure(def)
	if not _has_code(result, LevelValidator.ERR_FLOOR_NO_ASCENT):
		failures += _fail("plataforma isolada não gerou FLOOR_NO_ASCENT: %s" % str(result["errors"]))
	# FLOOR_NO_RETURN: relevo isolado sem relação com o canhão.
	# Em y=470 há vão de 100px até a base — fora do componente.
	def = _struct_def()
	var stray := FloorDefinition.new()
	stray.position = Vector2(600, 470)
	def.floors.append(stray)
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_FLOOR_NO_RETURN):
		failures += _fail("relevo isolado não gerou FLOOR_NO_RETURN")
	# OBSTACLE_FLOATING: dupla encostada entre si mas fora do floor.
	def = _struct_def()
	def.obstacles[0].position = Vector2(700, 300)
	def.obstacles[1].position = Vector2(800, 300)
	result = LevelValidator.validate_structure(def)
	if not _has_code(result, LevelValidator.ERR_OBSTACLE_FLOATING):
		failures += _fail("dupla flutuante não gerou OBSTACLE_FLOATING: %s" % str(result["errors"]))
	if _has_code(result, LevelValidator.ERR_OBSTACLE_ISOLATED):
		failures += _fail("dupla com aresta não deveria gerar OBSTACLE_ISOLATED")
	# OBSTACLE_ISOLATED: uma peça no floor + uma solitária flutuando.
	def = _struct_def()
	def.obstacles[1].position = Vector2(700, 300)
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_OBSTACLE_ISOLATED):
		failures += _fail("peça solitária não gerou OBSTACLE_ISOLATED")
	# STRUCTURE_UNGROUNDED: viga declarada com link inexistente.
	def = _struct_def()
	var beam := StructureDefinition.new()
	beam.id = "struct_01"
	beam.position = Vector2(1000, 400)
	beam.rotation_degrees = 90.0
	beam.role = StructureDefinition.ROLE_BEAM
	beam.link_a = "obs_01"
	beam.link_b = "obs_99"
	def.structures.append(beam)
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_STRUCTURE_UNGROUNDED):
		failures += _fail("viga com link quebrado não gerou STRUCTURE_UNGROUNDED")
	# TARGET_OUT_OF_ROLE: alvo fora da direita sem exceção.
	def = _struct_def()
	def.target.position = Vector2(700, 200)
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_TARGET_OUT_OF_ROLE):
		failures += _fail("alvo fora da direita não gerou TARGET_OUT_OF_ROLE")
	# TRIVIAL_COMPOSITION: base + canhão, zero obstáculos.
	def = _struct_def()
	def.obstacles.clear()
	if not _has_code(LevelValidator.validate_structure(def), LevelValidator.ERR_TRIVIAL_COMPOSITION):
		failures += _fail("fase vazia não gerou TRIVIAL_COMPOSITION")
	return failures


## Peças empilhadas com contato exato NÃO são sobreposição (a composição
## encosta; só penetração além da tolerância erra).
func _check_contact_allowed() -> int:
	var def := _struct_def()
	def.obstacles.clear()
	for i in 2:
		var stone := ObstacleDefinition.new()
		stone.id = "obs_%02d" % (i + 1)
		stone.kind = ObstacleDefinition.KIND_STONE
		stone.position = Vector2(700, 570 - i * 100) # encosto exato
		stone.group = Composition.GROUP_TOWER
		stone.anchor = "floor" if i == 0 else "obs_01"
		def.obstacles.append(stone)
	var legacy := LevelValidator.validate(def)
	if not legacy["ok"]:
		return _fail("torre encostada reprovada no validate(): %s" % str(legacy["errors"]))
	var result := LevelValidator.validate_structure(def)
	if not result["ok"]:
		return _fail("torre encostada reprovada: %s" % str(result["errors"]))
	return 0


## Números do Guide1: canhão (150,487)@0.3 sobre plataforma (150/250,570)
## + base contínua => apoio encontrado, subida conectada, sem erros de
## floor/canhão (o resto da fase não é montado aqui).
func _check_guide1_support() -> int:
	var def := LevelDefinition.new()
	def.cannon_position = Vector2(150, 487)
	def.cannon_scale = Vector2(0.3, 0.3)
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1150, 300)
	var x := 50.0
	while x <= 1250.0:
		var floor := FloorDefinition.new()
		floor.position = Vector2(x, 670)
		def.floors.append(floor)
		x += 100.0
	for px in [150.0, 250.0]:
		var platform := FloorDefinition.new()
		platform.position = Vector2(px, 570)
		def.floors.append(platform)
	for i in 2:
		var glass := ObstacleDefinition.new()
		glass.id = "obs_%02d" % (i + 1)
		glass.kind = ObstacleDefinition.KIND_GLASS
		glass.position = Vector2(950 + i * 100, 573)
		glass.scale = Vector2(0.1, 0.1)
		def.obstacles.append(glass)
	var result := LevelValidator.validate_structure(def)
	for code in [LevelValidator.ERR_FLOOR_GAP, LevelValidator.ERR_CANNON_FLOATING,
			LevelValidator.ERR_FLOOR_NO_ASCENT, LevelValidator.ERR_FLOOR_NO_RETURN]:
		if _has_code(result, code):
			return _fail("apoio do Guide1 gerou %s: %s" % [code, str(result["errors"])])
	return 0
