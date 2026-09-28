extends SceneTree
## Teste da composição (docs/plan.md, Etapas 4+): primitivas de execução
## (FloorShapes/StructureShapes) + vocabulário (Composition).
## Roda headless, sem framework e sem abrir cena:
##   godot --headless --path . -s res://components/level/tests/composition_test.gd
## Saída: "COMPOSITION_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).


func _init() -> void:
	var failures: int = 0
	failures += _check_floor_shapes()
	failures += _check_structure_shapes()
	failures += _check_composition_tags()
	if failures == 0:
		print("COMPOSITION_TEST: PASS")
	else:
		printerr("COMPOSITION_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


func _check_floor_shapes() -> int:
	# Base: 13 tiles 50..1250 em y=670.
	var base := FloorShapes.base()
	if base.size() != 13:
		return _fail("base deveria ter 13 tiles, veio %d" % base.size())
	if base[0].position != Vector2(50, 670) or base[12].position != Vector2(1250, 670):
		return _fail("base com extremos errados: %s / %s" % [str(base[0].position), str(base[12].position)])
	# Patamar do Guide1: platform(200, 570, 2) => (150,570)+(250,570).
	var platform := FloorShapes.platform(200, 570, 2)
	if platform.size() != 2 or platform[0].position != Vector2(150, 570):
		return _fail("platform Guide1 divergente: %s" % str(platform[0].position))
	if platform[1].position != Vector2(250, 570):
		return _fail("platform Guide1 divergente: %s" % str(platform[1].position))
	# Coluna do Guide2: 164..670 => 6 tiles.
	var column := FloorShapes.column(151, 164)
	if column.size() != 6 or column[0].position != Vector2(151, 164):
		return _fail("column Guide2 divergente: %d tiles" % column.size())
	if column[5].position != Vector2(151, 664):
		return _fail("column deveria terminar em 664, veio %s" % str(column[5].position))
	# Degraus: 3 tiles de (350,670) a (150,570).
	var steps := FloorShapes.steps(350, 670, 150, 570, 3)
	if steps.size() != 3 or steps[0].position != Vector2(350, 670):
		return _fail("steps com início errado")
	if steps[2].position != Vector2(150, 570):
		return _fail("steps com fim errado: %s" % str(steps[2].position))
	return 0


func _check_structure_shapes() -> int:
	# Viga horizontal entre torres: rotação 90, papel e links declarados.
	var beam := StructureShapes.beam("struct_01", Vector2(950, 344), Vector2(1050, 344), "obs_01", "obs_02")
	if beam.position != Vector2(1000, 344) or beam.rotation_degrees != 90.0:
		return _fail("beam com geometria errada: %s / %.1f" % [str(beam.position), beam.rotation_degrees])
	if beam.role != StructureDefinition.ROLE_BEAM or beam.link_b != "obs_02":
		return _fail("beam sem papel/links declarados")
	if beam.scale != Vector2(0.15, 0.15):
		return _fail("beam fora da escala dos guides")
	# Suporte vertical: rotação 0, destino é o Floor.
	var support := StructureShapes.support("struct_02", Vector2(434, 522), "obs_03")
	if support.rotation_degrees != 0.0 or support.role != StructureDefinition.ROLE_SUPPORT:
		return _fail("support com papel errado")
	if support.link_a != "obs_03" or support.link_b != "":
		return _fail("support com links errados")
	return 0


func _check_composition_tags() -> int:
	var comp := Composition.new()
	comp.cannon_intent = Composition.CANNON_PLATFORM
	comp.floor_profile = Composition.FLOOR_PLATFORM_L
	comp.target_role = Composition.TARGET_FOOT
	comp.groups = [
		{"type": Composition.GROUP_GATE, "mechanic": Composition.MECH_BREAKABLE},
		{"type": Composition.GROUP_TOWER, "mechanic": Composition.MECH_FRAME},
	]
	var tags := comp.summarize_tags()
	for expected in [Composition.CANNON_PLATFORM, Composition.FLOOR_PLATFORM_L,
			Composition.TARGET_FOOT, Composition.GROUP_GATE, Composition.MECH_BREAKABLE]:
		if not tags.has(expected):
			return _fail("tags sem %s: %s" % [String(expected), str(tags)])
	if tags.has(Composition.MECH_FRAME):
		return _fail("frame não é mecânica e não deveria entrar nas tags")
	var dict := comp.to_dict()
	if String(dict["cannon_intent"]) != "platform" or String(dict["floor_profile"]) != "platform_l":
		return _fail("to_dict da Composition divergente")
	return 0


func _fail(message: String) -> int:
	printerr("  [composition] " + message)
	return 1
