extends SceneTree
## Teste da tabela de materiais da Etapa 2 (DoD: tabela por tipo).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/material_rules_test.gd
## Saída: "MATERIAL_RULES_TEST: PASS" (exit 0) ou FAIL (exit 1).
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.


func _init() -> void:
	var failures: int = 0
	failures += _check_glass()
	failures += _check_stone()
	failures += _check_metal()
	failures += _check_unknown()
	failures += _check_geometry() # Etapa 2 (geometria de referência)
	if failures == 0:
		print("MATERIAL_RULES_TEST: PASS")
	else:
		printerr("MATERIAL_RULES_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


func _check_glass() -> int:
	# glass_obstacle.gd: 1HP, retain 0.85, atravessa (Area2D), sem rebote.
	if MaterialRules.max_hp(ObstacleDefinition.KIND_GLASS) != 1:
		return _fail("glass max_hp != 1")
	if MaterialRules.velocity_retain(ObstacleDefinition.KIND_GLASS) != 0.85:
		return _fail("glass retain != 0.85")
	if not MaterialRules.passes_through(ObstacleDefinition.KIND_GLASS):
		return _fail("glass deveria atravessar")
	if MaterialRules.bounces(ObstacleDefinition.KIND_GLASS):
		return _fail("glass não deveria rebotar")
	return 0


func _check_stone() -> int:
	# stone_obstacle.gd: stoneLife 2, retain 0.85, 1º hit rebate, 2º atravessa.
	if MaterialRules.max_hp(ObstacleDefinition.KIND_STONE) != 2:
		return _fail("stone max_hp != 2")
	if MaterialRules.velocity_retain(ObstacleDefinition.KIND_STONE) != 0.85:
		return _fail("stone retain != 0.85")
	if not MaterialRules.passes_through(ObstacleDefinition.KIND_STONE):
		return _fail("stone deveria atravessar ao destruir")
	if not MaterialRules.bounces(ObstacleDefinition.KIND_STONE):
		return _fail("stone deveria rebotar (bounce 1.0)")
	return 0


func _check_metal() -> int:
	# metal_obstacle.gd: indestrutível, bounce 1.0, sem atenuação por código.
	if MaterialRules.max_hp(ObstacleDefinition.KIND_METAL) != MaterialRules.INF_HP:
		return _fail("metal deveria ser indestrutível (INF_HP)")
	if MaterialRules.velocity_retain(ObstacleDefinition.KIND_METAL) != 1.0:
		return _fail("metal retain != 1.0 (código não atenua)")
	if MaterialRules.passes_through(ObstacleDefinition.KIND_METAL):
		return _fail("metal não deveria atravessar")
	if not MaterialRules.bounces(ObstacleDefinition.KIND_METAL):
		return _fail("metal deveria rebotar")
	return 0


func _check_unknown() -> int:
	if MaterialRules.is_known(&"adamantium"):
		return _fail("kind desconhecido reportado como conhecido")
	if MaterialRules.kinds().size() != 3:
		return _fail("kinds() deveria ter exatamente 3 materiais")
	return 0


## Etapa 2: geometria de referência da composição (medidas reais dos
## assets + pé do canhão calibrado no Guide1).
func _check_geometry() -> int:
	# structure.png 482x448; floor 500x500 (tscn + png).
	if MaterialRules.structure_size() != Vector2(482, 448):
		return _fail("structure_size != (482, 448)")
	if MaterialRules.floor_size() != Vector2(500, 500):
		return _fail("floor_size != (500, 500)")
	# Tile 0.2 = 100x100 (unidade da grade dos guides).
	if MaterialRules.floor_size() * Vector2(0.2, 0.2) != Vector2(100, 100):
		return _fail("tile 0.2 deveria ser 100x100")
	# Guide1: canhão (150, 487) @0.3 com plataforma centrada em y=570.
	var foot := Cannon.foot_position(Vector2(150, 487), Vector2(0.3, 0.3))
	if absf(foot.y - 570.0) > 1.0 or absf(foot.x - 150.0) > 0.001:
		return _fail("pé do Guide1 deveria ser ~(150, 570), veio %s" % str(foot))
	# Escala do jogo (0.2): pé ~55px abaixo da origem.
	var foot_game := Cannon.foot_position(Vector2(173, 523), Vector2(0.2, 0.2))
	if absf(foot_game.y - 578.4) > 1.0:
		return _fail("pé @0.2 deveria ser ~55px abaixo, veio %s" % str(foot_game))
	return 0


func _fail(message: String) -> int:
	printerr("  [material_rules] " + message)
	return 1
