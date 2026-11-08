extends SceneTree
## Regressão da feature: Sistema de Onomatopeias nos Impactos.
##
## Cobre os critérios de aceitação:
##  - todo impacto válido (stone, metal, vidro, chão) nasce 1 texto,
##    exatamente 1x, perto do ponto do impacto;
##  - Target e Shards NUNCA geram onomatopeia (guarda do roteador +
##    passagem real pela absorção do alvo);
##  - o caminho próprio do vidro (sinal do HitBox) e o raio da bala
##    compartilham o mesmo dedup: 1 hit() e 1 texto por impacto nos
##    DOIS ordens de chegada (sem duplicatas nem textos perdidos);
##  - limite rígido de 3 simultâneas, inclusive com várias colisões
##    no MESMO frame (evicção síncrona da mais antiga, que sai da
##    árvore e é liberada — não é só escondida);
##  - identidade: texto da lista predefinida, branco, fonte quadrada
##    arcade, rotação/deslocação aleatórias dentro dos limites;
##  - sem física, sem _process/_physics_process (Tween controla a vida);
##  - limpeza: após a animação o nó é liberado e a fila é prunada;
##  - sem gerenciador na cena: no-op sem erro (tests/guides).
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/impact-text/tests/impact_text_test.gd

const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const TARGET_SCENE: PackedScene = preload("res://components/target/target.tscn")
const FONT: Font = preload("res://assets/fonts/PressStart2P-Regular.ttf")

const CELL := 64.0
const OVERLAP := 1.01            # sobreposição 1.01 da arte (floor.tscn)
const TILE := CELL * OVERLAP
const CANNON_SCALE := 0.16
const FAST_SPEED := 2000.0       # shots/game.tscn base_shot_speed
const SPAWN_HEIGHT := 120.0
const MAX_FRAMES := 240
## Folga do deslocamento aleatório (jitter do gerenciador): o texto
## nasce no ponto do impacto + jitter, então a distância máxima é a
## hipotenusa do jitter (16,12) com a folga do próprio ponto de contato.
const POS_TOLERANCE := 26.0

var _failures := 0
var _world: Node2D
var _manager: ImpactTextManager
var _target_hits := 0


## Stone real com contador (mesmo padrão de stone_impact_test.gd): mede
## chamadas a hit() ANTES do super, provando o SISTEMA da bala não
## duplica — e, junto, que cada impacto vira exatamente 1 onomatopeia.
class CountingStone:
	extends StoneObstacle
	var hit_count := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hit_count += 1
		super.hit(bullet, impact_position)


class CountingMetal:
	extends MetalObstacle
	var hit_count := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hit_count += 1
		super.hit(bullet, impact_position)


## Vidro com contador de CHAMADAS a hit() (o super pode descartar a
## chamada via is_broken; o contador fica antes para provar que o
## roteador + sinal próprio não chamam 2x). O vidro é liberado no
## próprio hit(), então a contagem vive num holder EXTERNO do teste.
class CountingGlass:
	extends GlassObstacle
	var counter: Array = []

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		if counter.size() > 0:
			counter[0] = int(counter[0]) + 1
		super.hit(bullet, impact_position)


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await physics_frame
	# Gerenciador único, como no game.tscn (WorldArea/World/ImpactTexts).
	_manager = ImpactTextManager.new()
	root.add_child(_manager)
	_check(ImpactTextManager.current == _manager,
		"gerenciador publica referência estática em _ready")

	await _case_stone()
	await _case_metal()
	await _case_glass()
	await _case_floor()
	await _case_seam_two_impacts()
	await _case_target_no_text()
	await _case_shard_no_text()
	await _case_glass_direct_path()
	await _case_cap_same_frame()
	await _case_identity()
	await _case_cleanup()
	await _case_without_manager()

	if _failures == 0:
		print("IMPACT_TEXT_TEST: PASS")
	else:
		printerr("IMPACT_TEXT_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


## Impacto em pedra: exatamente 1 texto, perto da face atingida, e a
## física de ricochete continua intacta (1 hit, deflexão).
func _case_stone() -> void:
	await _begin_case()
	var stone := _make_counting_stone(Vector2.ZERO, Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var bounced := false
	var hit_seen := false
	for i in MAX_FRAMES:
		await physics_frame
		_assert_cap("stone")
		if not hit_seen and stone.hit_count >= 1:
			hit_seen = true
		if hit_seen and not bounced and is_instance_valid(bullet) \
				and bullet.linear_velocity.y < -1.0:
			bounced = true
			break
		if not is_instance_valid(bullet):
			break

	_check(hit_seen, "stone: impacto registrado 1x (hit_count=%d)" % stone.hit_count)
	_check(stone.hit_count == 1, "stone: sem hit duplicado (%d)" % stone.hit_count)
	_check(bounced, "stone: ricochete intacto (física preservada)")
	var texts := _texts()
	_check(texts.size() == 1,
		"stone: exatamente 1 onomatopeia (veio %d)" % texts.size())
	if texts.size() == 1:
		_assert_near_impact(texts[0], Vector2(0.0, -TILE * 0.5), "stone")
	await _settle(20)


## Impacto em metal: mesmo caminho da base (Obstacle.hit) — 1 texto.
func _case_metal() -> void:
	await _begin_case()
	var metal := _make_counting_metal(Vector2.ZERO, Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var hit_seen := false
	for i in MAX_FRAMES:
		await physics_frame
		_assert_cap("metal")
		if metal.hit_count >= 1:
			hit_seen = true
			break
		if not is_instance_valid(bullet):
			break

	_check(hit_seen, "metal: impacto registrado (hit_count=%d)" % metal.hit_count)
	_check(metal.hit_count == 1, "metal: sem hit duplicado (%d)" % metal.hit_count)
	var texts := _texts()
	_check(texts.size() == 1,
		"metal: exatamente 1 onomatopeia (veio %d)" % texts.size())
	if texts.size() == 1:
		_assert_near_impact(texts[0], Vector2(0.0, -TILE * 0.5), "metal")
	await _settle(20)


## Vidro atravessável: 1 texto, atenuação 0.85 intacta e os shards
## gerados não acrescentam nenhum texto.
func _case_glass() -> void:
	await _begin_case()
	var counter: Array = [0]
	var glass := _make_counting_glass(Vector2.ZERO, counter)
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var min_speed := INF
	var passed := false
	for i in 90:
		await physics_frame
		_assert_cap("glass")
		if not is_instance_valid(bullet):
			break
		min_speed = minf(min_speed, bullet.linear_velocity.length())
		if bullet.global_position.y > TILE:
			passed = true
			break

	_check(passed, "glass: bala atravessou o vidro")
	_check(int(counter[0]) == 1, "glass: 1 chamada de hit() (%d)" % int(counter[0]))
	_check(not is_instance_valid(glass), "glass: destruído (comportamento intacto)")
	_check(min_speed > 1400.0 and min_speed < 1900.0,
		"glass: atenuação 0.85 intacta (|v| mín=%.0f)" % min_speed)
	var texts := _texts()
	_check(texts.size() == 1,
		"glass: exatamente 1 onomatopeia, mesmo com shards voando (veio %d)"
		% texts.size())
	if texts.size() == 1:
		_assert_near_impact(texts[0], Vector2(0.0, -TILE * 0.5), "glass")
	await _settle(20)


## Chão (StaticBody2D sem hit(), como o floor real): ricochete também
## é impacto válido — 1 texto e NENHUM while a bala descansa (dedup
## por instância, sem spam por frame).
func _case_floor() -> void:
	await _begin_case()
	_make_floor_tile(Vector2.ZERO)
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var got := false
	for i in MAX_FRAMES:
		await physics_frame
		_assert_cap("floor")
		if _texts().size() >= 1:
			got = true
			break
		if not is_instance_valid(bullet):
			break

	_check(got, "floor: ricochete gerou onomatopeia")
	var texts := _texts()
	_check(texts.size() == 1,
		"floor: exatamente 1 onomatopeia no primeiro contato (veio %d)" % texts.size())
	# 30 frames com a bala em repouso/tocando: nenhum texto novo (o
	# primeiro pode expirar durante a espera, por isso acompanha o
	# máximo observado em vez do total no fim).
	var max_seen := _texts().size()
	for i in 30:
		await physics_frame
		_assert_cap("floor repouso")
		max_seen = maxi(max_seen, _texts().size())
	_check(max_seen == 1,
		"floor: sem spam durante o repouso (máx. observado %d)" % max_seen)
	await _settle(10)


## Junção pedra+pedra: dois elementos válidos no mesmo contato — cada
## um com seu texto, e o limite de 3 nunca estoura.
func _case_seam_two_impacts() -> void:
	await _begin_case()
	var left := _make_counting_stone(Vector2(-CELL * 0.5, 0.0), Vector2(TILE, TILE))
	var right := _make_counting_stone(Vector2(CELL * 0.5, 0.0), Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	for i in MAX_FRAMES:
		await physics_frame
		_assert_cap("junção")
		if left.hit_count >= 1 and right.hit_count >= 1:
			break
		if not is_instance_valid(bullet):
			break

	_check(left.hit_count == 1 and right.hit_count == 1,
		"junção: 1 hit por pedra (esq=%d dir=%d)" % [left.hit_count, right.hit_count])
	var texts := _texts()
	_check(texts.size() == 2,
		"junção: 1 onomatopeia por elemento, no limite (veio %d)" % texts.size())
	await _settle(20)


## Target: passagem real até a absorção — NENHUM texto durante todo o
## percurso, e a guarda do roteador recusa o nó diretamente.
func _case_target_no_text() -> void:
	await _begin_case()
	var target := TARGET_SCENE.instantiate() as Target
	target.position = Vector2(640.0, 360.0)
	target.scale = MaterialRules.target_scale()
	root.add_child(target)
	target.target_hit.connect(_on_target_hit)
	await physics_frame
	_target_hits = 0

	# Guarda unitária: o roteador recusa o Target (StaticBody2D sem
	# hit() — sem a guarda ele cairia no ramo de "elemento do cenário").
	var scratch: Bullet = BULLET_SCENE.instantiate() as Bullet
	_check(not scratch._route_hit(target, target.global_position),
		"route_hit(Target) = false")
	_check(_texts().size() == 0, "Target direto: nenhuma onomatopeia")
	scratch.free()

	# Passagem real: bala lenta caindo sobre o portal (caso comprovado
	# em black_hole_test) — absorvida sem nenhum texto no caminho.
	var bullet := await _spawn_bullet(
		Vector2(640.0, 360.0 - 70.0), Vector2(0.0, 40.0))
	for i in 300:
		await physics_frame
		_assert_cap("target")
		if _texts().size() > 0:
			break
		if _target_hits > 0 or not is_instance_valid(bullet):
			break

	_check(_target_hits == 1, "target: absorvida 1x (veio %d)" % _target_hits)
	_check(_texts().size() == 0,
		"target: passagem inteira sem onomatopeia (veio %d)" % _texts().size())
	if is_instance_valid(bullet):
		bullet.queue_free()
	target.queue_free()
	await _settle(5)


## Shards: o roteador os recusa explicitamente (e a colisão já é
## isolada pelas camadas — dupla proteção).
func _case_shard_no_text() -> void:
	await _begin_case()
	var scratch: Bullet = BULLET_SCENE.instantiate() as Bullet
	var shard := Shard.new()
	_check(not scratch._route_hit(shard, Vector2.ZERO),
		"route_hit(Shard) = false")
	_check(_texts().size() == 0, "Shard direto: nenhuma onomatopeia")
	shard.free()
	scratch.free()
	await _settle(3)


## Caminho próprio do vidro (body_entered do HitBox) nas DOIS ordens
## possíveis vs. o raio da bala: sempre 1 hit() e 1 texto.
func _case_glass_direct_path() -> void:
	# Ordem A: o sinal do vidro vence a corrida.
	await _begin_case()
	var counter_a: Array = [0]
	var glass_a := _make_counting_glass(Vector2.ZERO, counter_a)
	var bullet_a := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	# Simula o sinal ANTES de qualquer roteamento da bala.
	glass_a._on_hit_box_body_entered(bullet_a)
	_check(int(counter_a[0]) == 1, "ordem A: sinal próprio => 1 hit()")
	_check(_texts().size() == 1, "ordem A: sinal próprio => 1 texto (veio %d)"
		% _texts().size())
	# Depois o roteador "vê" a mesma área: no-op (dedup do pai).
	var area_a := glass_a.get_node_or_null("HitBox")
	if area_a != null:
		var routed := bullet_a._route_hit(area_a, Vector2.ZERO)
		_check(not routed, "ordem A: roteador não reprocessa o vidro")
	_check(int(counter_a[0]) == 1, "ordem A: hit() continua 1 (%d)" % int(counter_a[0]))
	_check(_texts().size() == 1, "ordem A: texto continua 1 (veio %d)" % _texts().size())
	if is_instance_valid(bullet_a):
		bullet_a.queue_free()
	await _settle(3)

	# Ordem B: o roteador vence; o sinal posterior é descartado.
	await _begin_case()
	var counter_b: Array = [0]
	var glass_b := _make_counting_glass(Vector2.ZERO, counter_b)
	var bullet_b := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	var area_b := glass_b.get_node_or_null("HitBox")
	var routed_b := false
	if area_b != null:
		routed_b = bullet_b._route_hit(area_b, Vector2.ZERO)
	_check(routed_b, "ordem B: roteador processa o HitBox")
	_check(int(counter_b[0]) == 1, "ordem B: 1 hit() (%d)" % int(counter_b[0]))
	_check(_texts().size() == 1, "ordem B: 1 texto (veio %d)" % _texts().size())
	# Sinal posterior (mesmo frame, antes do free): descartado.
	if is_instance_valid(glass_b):
		glass_b._on_hit_box_body_entered(bullet_b)
	_check(int(counter_b[0]) == 1, "ordem B: sinal não duplica hit() (%d)"
		% int(counter_b[0]))
	_check(_texts().size() == 1, "ordem B: sinal não duplica texto (veio %d)"
		% _texts().size())
	if is_instance_valid(bullet_b):
		bullet_b.queue_free()
	await _settle(3)


## Limite rígido: 10 spawns no MESMO frame (múltiplas colisões sem
## await entre elas) — nunca acima de 3, e a mais antiga sai da árvore
## e é liberada.
func _case_cap_same_frame() -> void:
	await _begin_case()
	_manager.spawn(Vector2.ZERO)
	var texts := _texts()
	_check(texts.size() == 1, "cap: 1º spawn cria 1 (veio %d)" % texts.size())
	var oldest: Node = texts[0]

	for i in 9:
		_manager.spawn(Vector2(float(i) * 5.0, 0.0))

	texts = _texts()
	_check(texts.size() == ImpactTextManager.MAX_ACTIVE,
		"cap: 10 spawns no mesmo frame => %d simultâneos (limite %d)" % [
			texts.size(), ImpactTextManager.MAX_ACTIVE])
	_check(_manager._active.size() == ImpactTextManager.MAX_ACTIVE,
		"cap: fila FIFO contém %d entradas (veio %d)" % [
			ImpactTextManager.MAX_ACTIVE, _manager._active.size()])
	_check(oldest.get_parent() == null,
		"cap: a mais antiga foi removida da árvore imediatamente")
	await physics_frame
	_check(not is_instance_valid(oldest),
		"cap: a mais antiga foi efetivamente liberada (queue_free)")
	texts = _texts()
	_check(texts.size() == ImpactTextManager.MAX_ACTIVE,
		"cap: após o frame seguem %d (veio %d)" % [
			ImpactTextManager.MAX_ACTIVE, texts.size()])
	await _settle(5)


## Identidade visual e variações: lista de textos, branco, fonte
## quadrada arcade, rotação/deslocação aleatórias e limites, sem
## física e sem _process (a vida é do Tween).
func _case_identity() -> void:
	await _begin_case()
	seed(7)  # sequência determinística para as asserções de variação
	var base := Vector2(320.0, 240.0)
	var spawned: Array[Node] = []
	for i in 8:
		_manager.spawn(base)
		var current := _texts()
		spawned.append(current[current.size() - 1])
		_assert_cap("identidade")

	var words := {}
	var rotations := {}
	var jitter_ok := true
	var style_ok := true
	var physics_free := true
	var process_free := true
	for node in spawned:
		if not is_instance_valid(node):
			continue
		var label := node.get_child(0) as Label
		if label == null:
			style_ok = false
			continue
		words[label.text] = true
		rotations[snappedf((node as Node2D).rotation_degrees, 0.001)] = true
		var dx: float = (node as Node2D).global_position.x - base.x
		var dy: float = (node as Node2D).global_position.y - base.y
		if absf(dx) > ImpactTextManager.JITTER_X \
				or absf(dy) > ImpactTextManager.JITTER_Y:
			jitter_ok = false
		if label.get_theme_font("font", "Label") != FONT \
				or label.get_theme_font_size("font_size", "Label") != ImpactText.FONT_SIZE \
				or label.get_theme_color("font_color", "Label") != ImpactText.TEXT_COLOR:
			style_ok = false
		if node is CollisionObject2D:
			physics_free = false
		if node.has_method("_process") or node.has_method("_physics_process"):
			process_free = false

	for word in words:
		if not ImpactTextManager.TEXTS.has(word):
			style_ok = false
	_check(words.size() >= 2, "identidade: textos variam (%d distintos)" % words.size())
	_check(rotations.size() >= 2,
		"identidade: rotações variam (%d distintas)" % rotations.size())
	for node in spawned:
		if not is_instance_valid(node):
			continue
		var rot: float = (node as Node2D).rotation_degrees
		if absf(rot) > ImpactText.MAX_ROTATION_DEG + 0.01:
			_check(false, "identidade: rotação %.2f° fora do limite ±%d°" % [
				rot, ImpactText.MAX_ROTATION_DEG])
	_check(jitter_ok, "identidade: deslocamento dentro do jitter (±%d,±%d)" % [
		ImpactTextManager.JITTER_X, ImpactTextManager.JITTER_Y])
	_check(style_ok,
		"identidade: fonte arcade do projeto, tamanho, branco e lista válida")
	_check(physics_free, "identidade: nenhum nó de texto é CollisionObject2D")
	_check(process_free,
		"identidade: sem _process/_physics_process (vida controlada por Tween)")
	await _settle(5)


## Ciclo de vida completo: após a animação o nó some da árvore e da
## memória, a fila é prunada no próximo spawn — sem vazamentos.
func _case_cleanup() -> void:
	await _begin_case()
	_manager.spawn(Vector2.ZERO)
	var texts := _texts()
	_check(texts.size() == 1, "cleanup: texto criado")
	if texts.is_empty():
		return
	var first: Node = texts[0]
	for i in 70:  # > LIFETIME (0.55s) com folga
		await physics_frame
		_assert_cap("cleanup")
	_check(not is_instance_valid(first),
		"cleanup: nó liberado após a animação (sem vazamento de nós)")
	_check(_texts().size() == 0,
		"cleanup: grupo vazio após a animação (veio %d)" % _texts().size())
	# A entrada morta só existe até o próximo spawn, que a pruna.
	_manager.spawn(Vector2.ZERO)
	_check(_manager._active.size() == 1,
		"cleanup: fila prunada no próximo spawn (veio %d)" % _manager._active.size())


## Sem gerenciador na cena (tests/guides): no-op silencioso.
func _case_without_manager() -> void:
	await _begin_case()
	_manager.queue_free()
	await physics_frame
	_check(ImpactTextManager.current == null,
		"sem gerenciador: referência estática limpa em _exit_tree")
	var stone := _make_counting_stone(Vector2.ZERO, Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	for i in MAX_FRAMES:
		await physics_frame
		if stone.hit_count >= 1 or not is_instance_valid(bullet):
			break
	_check(stone.hit_count == 1, "sem gerenciador: hit() segue funcionando (%d)"
		% stone.hit_count)
	_check(_texts().size() == 0, "sem gerenciador: nenhum texto (no-op)")
	_manager = null


func _on_target_hit(_body: Bullet) -> void:
	_target_hits += 1


## ------------------------------ helpers ------------------------------

func _texts() -> Array[Node]:
	return get_nodes_in_group("impact_texts")


func _assert_cap(where: String) -> void:
	var count := _texts().size()
	if count > ImpactTextManager.MAX_ACTIVE:
		_check(false, "%s: %d onomatopeias simultâneas > limite %d" % [
			where, count, ImpactTextManager.MAX_ACTIVE])


func _assert_near_impact(text: Node, impact: Vector2, where: String) -> void:
	var node := text as Node2D
	if node == null:
		_check(false, "%s: texto é Node2D" % where)
		return
	var dist := node.global_position.distance_to(impact)
	_check(dist <= POS_TOLERANCE,
		"%s: texto perto do impacto (dist=%.1f <= %.1f)" % [where, dist, POS_TOLERANCE])


func _begin_case() -> void:
	await _teardown()
	_clear_texts()
	_world = Node2D.new()
	root.add_child(_world)


## Remove da árvore e libera todos os textos (mesmo padrão de
## game.gd/_clear_transient_elements) — casos começam limpos.
func _clear_texts() -> void:
	for node in _texts():
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.queue_free()


func _spawn_bullet(pos: Vector2, vel: Vector2) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = pos
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = vel
	# deferred: o _ready da bala cria o trail no pai (padrão do
	# stone_impact_test.gd).
	_world.add_child.call_deferred(bullet)
	await physics_frame
	return bullet


func _make_counting_stone(pos: Vector2, size: Vector2) -> CountingStone:
	var stone := CountingStone.new()
	_add_obstacle_children(stone, size)
	stone.position = pos
	_world.add_child(stone)
	return stone


func _make_counting_metal(pos: Vector2, size: Vector2) -> CountingMetal:
	var metal := CountingMetal.new()
	_add_obstacle_children(metal, size)
	metal.position = pos
	_world.add_child(metal)
	return metal


## Vidro montado como glassObstacle.tscn (Sprite + HitBox Area2D com
## rect), sem depender de texturas no headless.
func _make_counting_glass(pos: Vector2, counter: Array) -> CountingGlass:
	var glass := CountingGlass.new()
	glass.counter = counter
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var area := Area2D.new()
	area.name = "HitBox"
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	col.shape = rect
	area.add_child(col)
	glass.add_child(sprite)
	glass.add_child(area)
	glass.position = pos
	_world.add_child(glass)
	return glass


func _add_obstacle_children(body: StaticBody2D, size: Vector2) -> void:
	if body is StoneObstacle:
		var cracked := Sprite2D.new()
		cracked.name = "CrackedStone"
		body.add_child(cracked)
		var polished := Sprite2D.new()
		polished.name = "PolishedStone"
		body.add_child(polished)
	else:
		body.add_child(Sprite2D.new())
	var col := CollisionShape2D.new()
	col.name = "HitBox"
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	body.add_child(col)


func _make_floor_tile(pos: Vector2) -> void:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	col.shape = rect
	body.add_child(col)
	body.position = pos
	_world.add_child(body)


func _settle(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)


func _teardown() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		_world = null
	await physics_frame
