extends SceneTree
## Teste do LevelBuilder da Etapa 7 (DoD parcial: rebuild idêntico).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/builder_test.gd
## Monta a mesma definição 2x e compara layout/grupos; o restante do DoD
## (solução manual vence, munição/derrota/vitória) é verificação humana
## no editor com a cena CannonController.
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.


func _initialize() -> void:
	super._initialize()
	_run_all() # async: precisa de 1 physics_frame por build


func _run_all() -> void:
	var failures: int = 0
	failures += await _case_rebuild_identical()
	if failures == 0:
		print("BUILDER_TEST: PASS")
	else:
		printerr("BUILDER_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


func _test_def() -> LevelDefinition:
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
	var stone := ObstacleDefinition.new()
	stone.id = "obs_02"
	stone.kind = ObstacleDefinition.KIND_STONE
	stone.position = Vector2(800, 300)
	def.obstacles.append(stone)
	var metal := ObstacleDefinition.new()
	metal.id = "obs_03"
	metal.kind = ObstacleDefinition.KIND_METAL
	metal.position = Vector2(400, 150)
	def.obstacles.append(metal)
	return def


func _case_rebuild_identical() -> int:
	var def := _test_def()
	var builder := LevelBuilder.new()
	root.add_child(builder)
	var world_a := Node2D.new()
	var world_b := Node2D.new()
	root.add_child(world_a)
	root.add_child(world_b)
	var first := await builder.build(world_a, def)
	var second := await builder.build(world_b, def)
	if world_a.get_child_count() != 4 or world_b.get_child_count() != 4:
		return _fail("filhos: %d/%d (esperado 4/4)" % [world_a.get_child_count(), world_b.get_child_count()])
	for i in 4:
		var node_a := world_a.get_child(i) as Node2D
		var node_b := world_b.get_child(i) as Node2D
		if node_a.position != node_b.position or node_a.scale != node_b.scale:
			return _fail("layouts divergem no filho %d" % i)
		if not node_a.is_in_group("level_spawned"):
			return _fail("filho %d fora do grupo level_spawned" % i)
	var target_a: Target = first["target"]
	if target_a == null or target_a.position != Vector2(1000, 200):
		return _fail("alvo ausente ou fora de posição")
	if (second["obstacles"] as Array).size() != 3:
		return _fail("obstáculos: %d (esperado 3)" % (second["obstacles"] as Array).size())
	# Rebuild no mesmo mundo: limpa antes, contagem estável.
	await builder.build(world_a, def)
	if world_a.get_child_count() != 4:
		return _fail("rebuild deixou %d filhos (esperado 4)" % world_a.get_child_count())
	return 0


func _fail(message: String) -> int:
	printerr("  [builder] " + message)
	return 1
