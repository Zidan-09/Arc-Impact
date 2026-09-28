extends SceneTree
## Teste do LevelBuilder (docs/plan.md, Etapa 7): concretiza a composição
## aprovada sem decidir nada — floors, structures, obstáculos, alvo com
## rotação e pose do canhão; rebuild idêntico; def legada sem floors usa
## a faixa plana legada.
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/builder_test.gd


func _initialize() -> void:
	_run_all() # async: precisa de 1 physics_frame por build


func _run_all() -> void:
	await physics_frame
	var failures: int = 0
	failures += await _case_composition_build()
	failures += await _case_legacy_ground()
	if failures == 0:
		print("BUILDER_TEST: PASS")
	else:
		printerr("BUILDER_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


## Def de composição: 2 floors + 1 viga + 2 obstáculos + alvo rotacionado.
func _test_def() -> LevelDefinition:
	var def := LevelDefinition.new()
	def.seed = 5
	def.ammo = 3
	def.cannon_position = Vector2(200, 465)
	def.cannon_scale = Vector2(0.2, 0.2)
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1150, 580)
	def.target.rotation_degrees = 90.0
	for fx in [150.0, 250.0]:
		var floor := FloorDefinition.new()
		floor.position = Vector2(fx, 570)
		def.floors.append(floor)
	var glass := ObstacleDefinition.new()
	glass.id = "obs_01"
	glass.kind = ObstacleDefinition.KIND_GLASS
	glass.position = Vector2(800, 573)
	glass.scale = Vector2(0.1, 0.1)
	def.obstacles.append(glass)
	var stone := ObstacleDefinition.new()
	stone.id = "obs_02"
	stone.kind = ObstacleDefinition.KIND_STONE
	stone.position = Vector2(930, 570)
	def.obstacles.append(stone)
	var beam := StructureDefinition.new()
	beam.id = "struct_01"
	beam.position = Vector2(865, 571)
	beam.rotation_degrees = 90.0
	beam.role = StructureDefinition.ROLE_BEAM
	beam.link_a = "obs_01"
	beam.link_b = "obs_02"
	def.structures.append(beam)
	return def


func _case_composition_build() -> int:
	var def := _test_def()
	var builder := LevelBuilder.new()
	root.add_child(builder)
	var world_a := Node2D.new()
	var world_b := Node2D.new()
	root.add_child(world_a)
	root.add_child(world_b)
	var first := await builder.build(world_a, def)
	var second := await builder.build(world_b, def)
	# 2 obstáculos + 1 alvo + 2 floors + 1 viga = 6 filhos.
	if world_a.get_child_count() != 6 or world_b.get_child_count() != 6:
		return _fail("filhos: %d/%d (esperado 6/6)" % [world_a.get_child_count(), world_b.get_child_count()])
	for i in 6:
		var node_a := world_a.get_child(i) as Node2D
		var node_b := world_b.get_child(i) as Node2D
		if node_a.position != node_b.position or node_a.scale != node_b.scale:
			return _fail("layouts divergem no filho %d" % i)
		if not node_a.is_in_group("level_spawned"):
			return _fail("filho %d fora do grupo level_spawned" % i)
	var target_a: Target = first["target"]
	if target_a == null or target_a.position != Vector2(1150, 580):
		return _fail("alvo ausente ou fora de posição")
	if target_a.rotation_degrees != 90.0:
		return _fail("alvo sem a rotação da composição")
	if (second["obstacles"] as Array).size() != 2:
		return _fail("obstáculos: %d (esperado 2)" % (second["obstacles"] as Array).size())
	if (first["floors"] as Array).size() != 2:
		return _fail("floors: %d (esperado 2)" % (first["floors"] as Array).size())
	if (first["structures"] as Array).size() != 1:
		return _fail("structures: %d (esperado 1)" % (first["structures"] as Array).size())
	if first["cannon_position"] != Vector2(200, 465):
		return _fail("pose do canhão divergente")
	if first["cannon_scale"] != Vector2(0.2, 0.2):
		return _fail("escala do canhão divergente")
	# Rebuild no mesmo mundo: limpa antes, contagem estável.
	await builder.build(world_a, def)
	if world_a.get_child_count() != 6:
		return _fail("rebuild deixou %d filhos (esperado 6)" % world_a.get_child_count())
	return 0


## Def legada (v1: sem floors/structures, alvo neutro) usa a faixa plana
## legada: 13 tiles + peças.
func _case_legacy_ground() -> int:
	var def := LevelDefinition.new()
	def.seed = 5
	def.ammo = 3
	def.target = TargetDefinition.new()
	def.target.position = Vector2(1000, 200)
	var glass := ObstacleDefinition.new()
	glass.id = "obs_01"
	glass.kind = ObstacleDefinition.KIND_GLASS
	glass.position = Vector2(600, 400)
	glass.scale = Vector2(0.1, 0.1)
	def.obstacles.append(glass)
	var builder := LevelBuilder.new()
	root.add_child(builder)
	var world := Node2D.new()
	root.add_child(world)
	var built := await builder.build(world, def)
	# 1 obstáculo + 1 alvo + 13 tiles legados = 15 filhos.
	if world.get_child_count() != 15:
		return _fail("legado: %d filhos (esperado 15)" % world.get_child_count())
	if (built["floors"] as Array).size() != 13:
		return _fail("legado: %d floors (esperado 13)" % (built["floors"] as Array).size())
	var target: Target = built["target"]
	if target == null or target.rotation_degrees != 0.0:
		return _fail("legado: alvo ausente ou rotacionado")
	return 0


func _fail(message: String) -> int:
	printerr("  [builder] " + message)
	return 1
