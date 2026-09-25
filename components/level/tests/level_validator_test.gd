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
