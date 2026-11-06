extends SceneTree
## Regressão do bug: bala atravessando a junção entre elementos sólidos
## adjacentes (e alta velocidade em geral). A superfície é montada com a
## geometria do jogo real: células de 64px (GridState.CELL_SIZE), tiles
## abutados com a leve sobreposição 1.01 da arte do floor.tscn, e a bala
## real (bullet.tscn, escala de canhão 0.16 => raio ~9.23px).
##
## Tiles são StaticBody2D de metal (bounce 1 / atrito 0) para que o
## ricochete pleno seja ASSERcionável (o floor.tscn real usa bounce 0.7 /
## atrito 0; aqui o espelho perfeito torna a asserção nítida).
##
## Cenários (todos com os 7 exigidos):
##  1. centro de um elemento (controle);
##  2. junção de 2 elementos;
##  3. canto: junção de 3 elementos (chão+parede), tiro diagonal;
##  4. junção de 2 em ALTA velocidade (6000 px/s);
##  5. junção de 2 em baixa velocidade (150 px/s);
##  6. junção de 2 com colisores sobrepostos (5%);
##  7/8. superfície longa (5 elementos): centro do do meio e junção
##       intermediária em alta velocidade.
##
## Critério único e rigoroso: o CENTRO da bala nunca pode entrar dentro do
## retângulo de nenhum tile (no contato o centro fica ~9px fora da face;
## tunelar é o centro atravessar a face). Somado a isso, em metal o
## ricochete tem de ocorrer (v.y vira negativa).
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/bullet/tests/seam_collision_test.gd

const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")

const CELL := 64.0                 # GridState.CELL_SIZE (RESOLUTION 2)
const CANNON_SCALE := 0.16         # Cannon.CANNON_SCALE / GridState.RESOLUTION
const BULLET_RADIUS := 57.717 * CANNON_SCALE  # raio real da bala no jogo
const FAST_SPEED := 2000.0         # screens/game.tscn base_shot_speed
const HIGH_SPEED := 6000.0         # 3x o tiro base (100px/passo a 60Hz)
const SLOW_SPEED := 150.0
const SPAWN_HEIGHT := 120.0
const MAX_FRAMES := 240

var _failures := 0
var _world: Node2D
var _tile_rects: Array[Rect2] = []
var _metal: PhysicsMaterial


func _initialize() -> void:
	_metal = PhysicsMaterial.new()
	_metal.bounce = 1.0   # ricochete pleno (e=1) => assertável
	_metal.friction = 0.0
	_run_all()


func _run_all() -> void:
	# 1. Controle: centro de um elemento.
	await _case_drop("centro de um elemento, %d px/s" % FAST_SPEED,
		3, 0.0, FAST_SPEED)
	# 2. O cenário reportado: junção de 2 elementos.
	await _case_drop("junção de 2 elementos, %d px/s" % FAST_SPEED,
		3, CELL * 0.5, FAST_SPEED)
	# 3. Canto: 3 elementos (chão esquerdo + chão direito + parede),
	#    tiro diagonal de 45° exatamente contra o vértice do canto.
	await _case_corner("canto de 3 elementos (tiro diagonal), %d px/s" % FAST_SPEED,
		FAST_SPEED)
	# 4. Junção em alta velocidade: 100px/passo, passa do raio+tamanho
	#    da junção de uma vez (tunelava até em tile único antes).
	await _case_drop("junção de 2 elementos, %d px/s (alta)" % HIGH_SPEED,
		3, CELL * 0.5, HIGH_SPEED)
	# 5. Junção em baixa velocidade.
	await _case_drop("junção de 2 elementos, %d px/s (baixa)" % SLOW_SPEED,
		3, CELL * 0.5, SLOW_SPEED)
	# 6. Sobreposição ampliada entre colisores (5% em vez de 1%).
	await _case_drop("junção de 2 com sobreposição 5%%, %d px/s" % FAST_SPEED,
		3, CELL * 0.5, FAST_SPEED, 1.05)
	# 7. Superfície longa: centro do elemento do meio.
	await _case_drop("superfície de 5: centro do do meio, %d px/s" % FAST_SPEED,
		5, 0.0, FAST_SPEED)
	# 8. Superfície longa: junção intermediária em alta velocidade.
	await _case_drop("superfície de 5: junção intermediária, %d px/s" % HIGH_SPEED,
		5, CELL * 0.5, HIGH_SPEED)
	# 9. Repouso em superfície sem material (bounce 0 / atrito 1, p. ex.
	#    parede do cano; o floor.tscn agora tem bounce 0.7): a bala para
	#    sobre a superfície e permanece fora dos tiles (valida o caminho de
	#    repouso do CCD, que deixa o empuxo do motor resolver sem congelar
	#    nem afundar).
	await _case_absorb_rest("repouso em superfície sem material, %d px/s" % FAST_SPEED)

	if _failures == 0:
		print("SEAM_COLLISION_TEST: PASS")
	else:
		printerr("SEAM_COLLISION_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


## Cenário padrão: `tiles` elementos lado a lado (topo em y=0), bala
## caindo verticalmente sobre `offset_x` (0 = centro do tile do meio,
## CELL/2 = junção com tiles dos dois lados), velocidade `speed`.
## `shape_extra_scale` amplia os colisores (testa sobreposição maior).
func _case_drop(
	msg: String, tiles: int, offset_x: float, speed: float,
	shape_extra_scale: float = 1.01
) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	for i in tiles:
		var x := (float(i) - (tiles - 1) * 0.5) * CELL
		_make_tile(Vector2(x, CELL * 0.5), shape_extra_scale, _metal)

	var spawn := Vector2(offset_x, -SPAWN_HEIGHT)
	var vel := Vector2(0.0, speed)
	await _run_bullet(msg, spawn, vel)


## Canto de 3 elementos: chão (2 tiles, junção em x=0) + parede apoiada
## no chão à direita. Vértice do canto em (0, 0); a bala vem na diagonal
## de 45° e tem de ser defletida de volta para cima-esquerda.
func _case_corner(msg: String, speed: float) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	_make_tile(Vector2(-CELL * 0.5, CELL * 0.5), 1.01, _metal)  # chão esquerdo
	_make_tile(Vector2(CELL * 0.5, CELL * 0.5), 1.01, _metal)   # chão direito
	_make_tile(Vector2(CELL * 0.5, -CELL * 0.5), 1.01, _metal)  # parede sobre o chão

	var diag := speed / sqrt(2.0)
	await _run_bullet(msg, Vector2(-150.0, -150.0), Vector2(diag, diag))


## Repouso: chão com material padrão (bounce 0 / atrito 1, sem override —
## como as paredes do cano; o floor.tscn real tem bounce 0.7 / atrito 0).
## A bala cai, para na superfície e permanece fora dos tiles pelo resto da
## simulação.
func _case_absorb_rest(msg: String) -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	for i in 3:
		var x := (float(i) - 1.0) * CELL
		_make_tile(Vector2(x, CELL * 0.5), 1.01, null)  # material padrão

	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = Vector2(0.0, -SPAWN_HEIGHT)
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = Vector2(0.0, FAST_SPEED)
	_world.add_child.call_deferred(bullet)
	await physics_frame

	var tunneled := false
	for i in MAX_FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		if _inside_any_tile(bullet.global_position):
			tunneled = true
			break
		if i >= 120:
			break

	var speed := bullet.linear_velocity.length() if is_instance_valid(bullet) else INF
	var y := bullet.global_position.y if is_instance_valid(bullet) else INF
	_check(not tunneled, "%s => nunca entrou no tile" % msg)
	_check(speed < 50.0, "%s => parou sobre a superfície: |v|=%.1f (y=%.2f)" % [msg, speed, y])
	_teardown()


## Executa a bala real e valida: nunca dentro de tile + ricochete.
func _run_bullet(msg: String, spawn: Vector2, vel: Vector2) -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = spawn
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = vel
	# deferred: o _ready da bala cria o trail no pai, e o pai está "busy"
	# montando filhos quando o add_child é síncrono aqui (fora do jogo).
	_world.add_child.call_deferred(bullet)
	await physics_frame

	var tunneled := false
	var bounced := false
	var deepest := -INF
	var tunnel_at := Vector2.INF
	for i in MAX_FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		var pos := bullet.global_position
		deepest = maxf(deepest, pos.y)
		if _inside_any_tile(pos):
			tunneled = true
			tunnel_at = pos
			break
		if i > 5 and bullet.linear_velocity.y < -1.0:
			bounced = true
			break

	_check(not tunneled, "%s => %s (y mais baixo do centro=%.2f%s)" % [
		msg,
		"ATRAVESSOU" if tunneled else "bloqueado",
		deepest,
		"" if not tunneled else ", ponto de tunelamento=%s" % str(tunnel_at),
	])
	var final_v := bullet.linear_velocity if is_instance_valid(bullet) else Vector2.INF
	_check(bounced, "%s => ricochete em metal: %s (v final=%s)" % [
		msg, "SIM" if bounced else "NAO", str(final_v),
	])
	_teardown()


func _make_tile(pos: Vector2, extra_scale: float, mat: PhysicsMaterial = null) -> void:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(CELL, CELL) * extra_scale
	col.shape = rect
	body.add_child(col)
	body.position = pos
	body.physics_material_override = mat
	_world.add_child(body)
	_tile_rects.append(Rect2(pos - rect.size * 0.5, rect.size))


func _inside_any_tile(pos: Vector2) -> bool:
	for r in _tile_rects:
		if r.has_point(pos):
			return true
	return false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)


func _teardown() -> void:
	_tile_rects.clear()
	if is_instance_valid(_world):
		_world.queue_free()
		_world = null
	await physics_frame
