extends SceneTree
## Regressão: impactos em obstáculos stone precisam ser contabilizados
## EXATAMENTE 1x por contato físico, em todas as velocidades e junções.
## Introduzido junto com o CCD preditivo: o clamp impede o overlap físico
## com sólidos, então o `body_entered` (fonte antiga do hit) não dispara
## mais — a comunicação passou a depender só do raio de `_swept_check`,
## que parte do CENTRO da bala (sempre ≥ raio da face, pelo próprio
## clamp) e não alcança a superfície quando o passo/tick é curto
## (baixa velocidade), no rasante, ou quando um tile sem `hit()` (chão)
## é o primeiro atingido na junção (break do loop de varredura).
##
## Cada cenário dispara a bala REAL (bullet.tscn, escala 0.16) contra o
## obstáculo real (StoneObstacle/MetalObstacle, contados por subclasse
## com contador de hit()) e asserts:
##  - hit_count == 1 ao final de 200 frames (exatamente-uma-vez: nem
##    perdido, nem duplicado por contatos repetidos no mesmo ricochete);
##  - ricochete ocorre (pedra/metal têm bounce 1) — prova de que a
##    física rebateu NO MESMO contato que o hit() teria de registrar;
##  - o centro da bala nunca entra no sólido (guarda da correção de
##    tunelamento nas junções);
##  - pedra real: 1º impacto mantém viva com stoneLife 1; 2º destroi.
##  - vidro (Area2D, atravessável): atenuação 0.85 intacta, 1 hit, passa.
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/bullet/tests/stone_impact_test.gd

const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const STONE_SCENE: PackedScene = preload("res://components/obstacles/stone/stoneObstacle.tscn")

const CELL := 64.0
const OVERLAP := 1.01            # sobreposição 1.01 da arte (floor.tscn)
const TILE := CELL * OVERLAP
const STONE_SCENE_SIZE := 500.0  # tamanho base do rect da cena stone
const CANNON_SCALE := 0.16
const FAST_SPEED := 2000.0       # shots/game.tscn base_shot_speed
const HIGH_SPEED := 6000.0
const MID_SPEED := 400.0         # passo ~6.7px < raio 9.23px: o raio do
                                 # centro não alcança a face no contato
const SLOW_SPEED := 150.0
const SPAWN_HEIGHT := 120.0

var _failures := 0
var _world: Node2D


## Stone real com contador: mede chamadas a hit() (a dedup base
## `is_processing_hit` engoliria duplicatas DENTRO do base; o contador
## fica ANTES do super para provar que o SISTEMA da bala chamou 1x).
class CountingStone:
	extends StoneObstacle
	var hit_count := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hit_count += 1
		super.hit(bullet, impact_position)


## Metal real com contador (metal_obstacle.gd tem hit() da base).
class CountingMetal:
	extends MetalObstacle
	var hit_count := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hit_count += 1
		super.hit(bullet, impact_position)


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# 1. Controle: centro da pedra em alta velocidade (o raio de 33px
	#    alcança a face — caso que JÁ funcionava pós-CCD).
	await _case_stone_drop("pedra centro, %d px/s" % FAST_SPEED,
		FAST_SPEED, 0.0)
	# 2. Centro em altíssima velocidade (100px/passo).
	await _case_stone_drop("pedra centro, %d px/s" % HIGH_SPEED,
		HIGH_SPEED, 0.0)
	# 3. Baixa velocidade: passo 6.7px < raio — o raio do centro não
	#    alcança a face; o contato/ricochete só existe no CCD.
	await _case_stone_drop("pedra centro, %d px/s" % MID_SPEED,
		MID_SPEED, 0.0)
	# 4. Baixa velocidade extrema (passo 2.5px).
	await _case_stone_drop("pedra centro, %d px/s" % SLOW_SPEED,
		SLOW_SPEED, 0.0)
	# 5. Rasante: a bala morde o canto da pedra; o raio do centro passa
	#    ao lado do retângulo, mas o shape da bala toca o canto. Sem
	#    deflexão esperada (pré-CCD o passo discreto pulava esse contato
	#    raso; o motor dava só empurrão lateral) — só hit 1x + sem tunelar.
	await _case_stone_drop("pedra rasante no canto, %d px/s" % FAST_SPEED,
		FAST_SPEED, TILE * 0.5 + 9.23 - 3.0, 1, false)
	# 6. Junção pedra+chão: raio atinge o chão primeiro (sem hit()) e
	#    para a varredura; o CCD toca chao+pedra no canto.
	await _case_junction("junção pedra+chão, %d px/s" % FAST_SPEED,
		FAST_SPEED)
	# 7. Junção pedra+pedra: cada pedra com contato válido leva 1 hit.
	await _case_stone_seam("junção pedra+pedra, %d px/s" % FAST_SPEED,
		FAST_SPEED)
	# 8. Cena real de pedra: 1º impacto mantém (stoneLife 1), 2º destrói.
	await _case_two_hits("pedra real: 2 impactos separamos, %d px/s" % FAST_SPEED)
	# 9. Metal inalterado: 1 hit + ricochete (mesmo caminho de roteamento).
	await _case_metal("metal centro, %d px/s" % FAST_SPEED)
	# 10. Vidro inalterado: atravessa com atenuação 0.85, 1 hit.
	await _case_glass("vidro atravessável, %d px/s" % FAST_SPEED)

	if _failures == 0:
		print("STONE_IMPACT_TEST: PASS")
	else:
		printerr("STONE_IMPACT_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


## Pedra de contagem em (0,0); bala cai verticalmente sobre `offset_x`
## com `speed`. Ao final: exatamente `expect_hits` chamadas de hit(),
## ricochete ocorrido e o centro da bala nunca dentro do sólido.
## `expect_deflection=false` para o rasante: o passo discreto pré-CCD
## pulava esse contato raso e o motor dava só um empurrão lateral
## (vn=0 na normal de face => sem ricochete); o CCD reproduz o mesmo
## comportamento (bounce no-op) — sem regressão. O que se afirma:
## hit contabilizado 1x + o centro nunca entra na pedra.
func _case_stone_drop(msg: String, speed: float, offset_x: float,
	expect_hits: int = 1, expect_deflection: bool = true) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var stone := _make_counting_stone(Vector2(0.0, 0.0), Vector2(TILE, TILE))
	var top := -TILE * 0.5
	var bullet := await _spawn_bullet(
		Vector2(offset_x, top - SPAWN_HEIGHT), Vector2(0.0, speed))

	var deflected := false
	var tunneled := false
	for i in 240:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		# Deflexão: cima (ricochete) OU lateral (rasante no canto empurra
		# para o lado; a norma do contato é mais horizontal que vertical).
		if bullet.linear_velocity.y < -1.0 or bullet.linear_velocity.x > 1.0:
			deflected = true
		if stone != null and _inside_rect(bullet.global_position, stone_rect()):
			tunneled = true

	_check(stone.hit_count == expect_hits,
		"%s => hits contabilizados: %d (esperado %d)" % [msg, stone.hit_count, expect_hits])
	if expect_deflection:
		_check(deflected, "%s => deflexão após o contato (v=%s)" % [
			msg, str(bullet.linear_velocity) if is_instance_valid(bullet) else "inválida"])
	_check(not tunneled, "%s => centro da bala nunca entrou na pedra" % msg)
	_teardown()


## Junção pedra+chão: pedra em (0,0), chão (StaticBody2D puro, sem
## hit()) em (CELL,0). Bala a 33px — do lado do chão, mas o shape da
## bala morde o canto da pedra no contato.
func _case_junction(msg: String, speed: float) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var stone := _make_counting_stone(Vector2(0.0, 0.0), Vector2(TILE, TILE))
	_make_floor_tile(Vector2(CELL, 0.0))
	var top := -TILE * 0.5
	var bullet := await _spawn_bullet(
		Vector2(TILE * 0.5 + 0.7, top - SPAWN_HEIGHT), Vector2(0.0, speed))

	var bounced := false
	var tunneled := false
	for i in 240:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		if bullet.linear_velocity.y < -1.0:
			bounced = true
		if _inside_rect(bullet.global_position, stone_rect()):
			tunneled = true

	_check(stone.hit_count == 1,
		"%s => pedra registrou: %d hit(s)" % [msg, stone.hit_count])
	_check(bounced, "%s => ricochete após o contato" % msg)
	_check(not tunneled, "%s => centro da bala nunca entrou na pedra" % msg)
	_teardown()


## Junção pedra+pedra (seam de elementos iguais): o contato do shape da
## bala alcança AS DUAS pedras — cada uma leva exatamente 1 hit.
func _case_stone_seam(msg: String, speed: float) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var left := _make_counting_stone(Vector2(-CELL * 0.5, 0.0), Vector2(TILE, TILE))
	var right := _make_counting_stone(Vector2(CELL * 0.5, 0.0), Vector2(TILE, TILE))
	var top := -TILE * 0.5
	var bullet := await _spawn_bullet(Vector2(0.0, top - SPAWN_HEIGHT), Vector2(0.0, speed))

	for i in 240:
		await physics_frame
		if not is_instance_valid(bullet):
			break

	var total: int = left.hit_count + right.hit_count
	_check(left.hit_count == 1 and right.hit_count == 1,
		"%s => hits por pedra: esq=%d dir=%d (total %d; cada contato válido 1x)" % [
			msg, left.hit_count, right.hit_count, total])
	_teardown()


## Cena real stoneObstacle.tscn: bala 1 => stoneLife 2→1 (pedra vive,
## textura rachada); bala 2 => destruída. Espaçadas > tempo da animação
## (0.3s) — a dedup is_processing_hit da base é comportamento projetado.
func _case_two_hits(msg: String) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var stone := STONE_SCENE.instantiate() as StoneObstacle
	stone.scale = Vector2(CELL / STONE_SCENE_SIZE, CELL / STONE_SCENE_SIZE)
	stone.position = Vector2(0.0, 0.0)
	_world.add_child(stone)
	var top := -TILE * 0.5

	var bullet1 := await _spawn_bullet(
		Vector2(0.0, top - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	for i in 45:  # 0.75s: animação do 1º hit completa (life 2→1)
		await physics_frame

	_check(is_instance_valid(stone), "%s => 1º impacto: pedra ainda existe" % msg)
	if is_instance_valid(stone):
		_check(stone.stoneLife == 1 and not stone.is_destroyed,
			"%s => 1º impacto: stoneLife=%d, is_destroyed=%s" % [
				msg, stone.stoneLife, str(stone.is_destroyed)])

	var bullet2 := await _spawn_bullet(
		Vector2(0.0, top - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	for i in 45:
		await physics_frame
		if not is_instance_valid(stone):
			break

	_check(not is_instance_valid(stone),
		"%s => 2º impacto: pedra destruída" % msg)
	if is_instance_valid(bullet2):
		var p := bullet2.global_position
		var sane := absf(p.x) < 5000.0 and absf(p.y) < 5000.0
		_check(sane and is_instance_valid(bullet2),
			"%s => bala 2 íntegra após o shatter (pos=%s |v|=%.0f)" % [
				msg, str(p), bullet2.linear_velocity.length()])
	_teardown()


## Metal (mesmo mecanismo de hit() da base): inalterado — 1 hit, 1
## ricochete, sem duplicata.
func _case_metal(msg: String) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var metal := _make_counting_metal(Vector2(0.0, 0.0), Vector2(TILE, TILE))
	var top := -TILE * 0.5
	var bullet := await _spawn_bullet(Vector2(0.0, top - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var bounced := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		if bullet.linear_velocity.y < -1.0:
			bounced = true

	_check(metal.hit_count == 1,
		"%s => hits contabilizados: %d (esperado 1)" % [msg, metal.hit_count])
	_check(bounced, "%s => ricochete em metal" % msg)
	_teardown()


## Vidro (Area2D atravessável, hit() próprio via body_entered do HitBox):
## inalterado — atravessa atenuado (×0.85), 1 hit, sem ricochete.
func _case_glass(msg: String) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var glass := GlassObstacle.new()
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
	glass.position = Vector2(0.0, 0.0)
	_world.add_child(glass)

	var glass_y := 0.0
	var top := -TILE * 0.5
	var bullet := await _spawn_bullet(Vector2(0.0, top - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var min_speed := INF
	var passed := false
	for i in 60:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		min_speed = minf(min_speed, bullet.linear_velocity.length())
		if bullet.global_position.y > glass_y + TILE:
			passed = true
			break

	_check(passed, "%s => bala atravessou o vidro (y=%.0f)" % [
		msg, bullet.global_position.y if is_instance_valid(bullet) else INF])
	_check(not is_instance_valid(glass),
		"%s => vidro quebrou (1 hit, sem duplicata)" % msg)
	_check(min_speed > 1400.0 and min_speed < 1900.0,
		"%s => atenuação 0.85 intacta: |v| mínima=%.0f (esperado ~1700)" % [msg, min_speed])
	_teardown()


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


## Reproduz a estrutura das cenas stone/metal (Sprite2D + HitBox
## CollisionShape2D com rect) sem depender de texturas no headless.
## stone_obstacle.gd referencia $CrackedStone/$PolishedStone via @onready.
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


func _spawn_bullet(pos: Vector2, vel: Vector2) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = pos
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = vel
	# deferred: o _ready da bala cria o trail no pai (padrão do
	# seam_collision_test.gd).
	_world.add_child.call_deferred(bullet)
	await physics_frame
	return bullet


func stone_rect() -> Rect2:
	return Rect2(Vector2(-TILE * 0.5, -TILE * 0.5), Vector2(TILE, TILE))


func _inside_rect(pos: Vector2, rect: Rect2) -> bool:
	return rect.has_point(pos)


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

