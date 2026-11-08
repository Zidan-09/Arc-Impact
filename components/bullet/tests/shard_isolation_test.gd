extends SceneTree
## Regressão: isolamento completo Bullet↔Shards resolvido SÓ por
## collision_layer/collision_mask (sem lógica manual), com o comportamento
## dos fragmentos preservado. Cenários:
##  1. Configuração das cenas: bala layer 2 / mask 3; shards (glass e
##     stone) layer 8 (camada 4) / mask 9 (cenário 1 + shards 4);
##     BulletReturnDetector e HitBox do vidro com mask 3 (a detecção de
##     Area2D é direcional: area.mask & body.layer).
##  2. Bala atravessa um shard sem NENHUMA interferência: velocidade e
##     trajetória intactas, shard intocado, zero contatos body_entered.
##  3. Shard cai com gravidade e repousa sobre o chão (StaticBody2D 1/1):
##     física e colisão com o cenário intactas.
##  4. Shard colide com outro shard: dispersão entre fragmentos intacta.
##  5. Bala ainda trava/ricocheteia no sólido do mundo (máscara intacta).
##  6. Bala↔bala ainda colide (o mask 3 mantém o conjunto visível do
##     antigo mask 1: balas na camada 1+2 eram enxergadas pelo bit 1).
## Fixtures (gravidade zerada em instância, lifetime estendido) isolam
## variáveis; as cenas permanecem intactas.
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/bullet/tests/shard_isolation_test.gd

const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const CANNON_SCENE: PackedScene = preload("res://components/cannon/cannon.tscn")
const GLASS_SCENE: PackedScene = preload("res://components/obstacles/glass/glassObstacle.tscn")
const GLASS_SHARD_SCENE: PackedScene = preload("res://components/obstacles/glass/glass_shard_1.tscn")
const STONE_SHARD_SCENE: PackedScene = preload("res://components/obstacles/stone/stone_shard_1.tscn")

const CANNON_SCALE := 0.16
const SHARD_LAYER := 8    # camada 4 (valor 8), exclusiva dos fragmentos
const SHARD_MASK := 9     # cenário (bit 1) + shards (bit 4)
const FLOOR_TOP := -100.0

var _failures := 0
var _world: Node2D
var _shard_contacts := 0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await physics_frame
	await _case_config()
	await _case_bullet_through_shard()
	await _case_shard_falls_on_floor()
	await _case_shard_vs_shard()
	await _case_bullet_hits_world()
	await _case_bullet_vs_bullet()

	if _failures == 0:
		print("SHARD_ISOLATION_TEST: PASS")
	else:
		printerr("SHARD_ISOLATION_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)


## 1. Invariantes de camada/máscara nas cenas reais.
func _case_config() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	_check(bullet.collision_layer == 2,
		"bala layer=2 (só 'pode ser atraído'), veio %d" % bullet.collision_layer)
	_check(bullet.collision_mask == 3,
		"bala mask=3 (mundo+balas), veio %d" % bullet.collision_mask)
	bullet.free()

	for scene in [STONE_SHARD_SCENE, GLASS_SHARD_SCENE]:
		var shard := scene.instantiate() as RigidBody2D
		_check(shard.collision_layer == SHARD_LAYER,
			"%s layer=8 (camada 4 dos shards), veio %d" % [shard.name, shard.collision_layer])
		_check(shard.collision_mask == SHARD_MASK,
			"%s mask=9 (cenário 1 + shards 4), veio %d" % [shard.name, shard.collision_mask])
		shard.free()

	var cannon := CANNON_SCENE.instantiate()
	var detector := cannon.get_node_or_null("BarrelPivot/BulletReturnDetector") as Area2D
	_check(detector != null and detector.collision_mask == 3,
		"BulletReturnDetector mask=3 (detecta a bala sem a camada 1), veio %s" % (
			str(detector.collision_mask) if detector != null else "ausente"))
	cannon.free()

	var glass := GLASS_SCENE.instantiate()
	var hit_box := glass.get_node_or_null("HitBox") as Area2D
	_check(hit_box != null and hit_box.collision_mask == 3,
		"HitBox do vidro mask=3 (detecta a bala sem a camada 1), veio %s" % (
			str(hit_box.collision_mask) if hit_box != null else "ausente"))
	glass.free()


## 2. Bala atravessa o shard: vx/trajetória intactas, shard intocado,
## nenhum contato entre eles.
func _case_bullet_through_shard() -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var shard := _spawn_shard(STONE_SHARD_SCENE, Vector2.ZERO, false)
	var bullet := await _spawn_bullet(Vector2(-400, 0), Vector2(600, 0), false)
	# Controle em voo livre (longe do shard): absorve o damp global do
	# projeto — a bala testada precisa terminar com a MESMA velocidade
	# que a de controle, prova de que nada a desviou ou freou.
	var control := await _spawn_bullet(Vector2(-400, -500), Vector2(600, 0), false)
	_shard_contacts = 0
	bullet.body_entered.connect(_on_bullet_body_entered)

	var bullet_deflected := false
	var shard_moved := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(bullet) or not is_instance_valid(shard) \
				or not is_instance_valid(control):
			break
		if absf(bullet.global_position.y) > 1.0:
			bullet_deflected = true
		if shard.linear_velocity.length() > 1.0:
			shard_moved = true

	_check(is_instance_valid(bullet) and is_instance_valid(shard)
		and is_instance_valid(control),
		"bala, controle e shard seguem válidos após o cruzamento")
	if is_instance_valid(bullet):
		_check(not bullet_deflected,
			"bala sem desvio vertical (y=%.1f)" % bullet.global_position.y)
		_check(bullet.global_position.x > 200.0,
			"bala completou a travessia (x=%.0f)" % bullet.global_position.x)
		if is_instance_valid(control):
			_check(absf(bullet.linear_velocity.x - control.linear_velocity.x) < 1.0,
				"vx idêntica ao voo livre: bala=%.2f controle=%.2f (sem freio/desvio)" % [
					bullet.linear_velocity.x, control.linear_velocity.x])
			_check(absf(bullet.linear_velocity.y - control.linear_velocity.y) < 1.0,
				"vy idêntica ao voo livre: bala=%.2f controle=%.2f" % [
					bullet.linear_velocity.y, control.linear_velocity.y])
	if is_instance_valid(shard):
		_check(not shard_moved,
			"shard intocado: v=%s" % str(shard.linear_velocity))
	_check(_shard_contacts == 0,
		"nenhum body_entered bala↔shard (contatos=%d)" % _shard_contacts)
	_teardown()


## 3. Shard cai no chão (StaticBody2D 1/1) e repousa: gravidade e
## colisão com o cenário intactas.
func _case_shard_falls_on_floor() -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	_make_static_rect(Vector2(0, 100), Vector2(600, 400))  # topo em -100
	var shard := _spawn_shard(GLASS_SHARD_SCENE, Vector2(0, -300), true)
	shard.linear_velocity = Vector2(0, 150)

	var fell_through := false
	for i in 240:  # 4s: queda + amortecimento dos ricochetes (e=0.3)
		await physics_frame
		if not is_instance_valid(shard):
			break
		if shard.global_position.y > FLOOR_TOP + 60.0:
			fell_through = true
			break

	_check(is_instance_valid(shard), "shard segue válido (não expirou)")
	if is_instance_valid(shard):
		_check(not fell_through,
			"shard não atravessou o chão (y=%.1f)" % shard.global_position.y)
		_check(shard.global_position.y < FLOOR_TOP + 10.0,
			"shard repousa sobre o topo do chão (y=%.1f, topo=%.0f)" % [
				shard.global_position.y, FLOOR_TOP])
		_check(absf(shard.linear_velocity.y) < 40.0,
			"shard assentou (vy=%.1f)" % shard.linear_velocity.y)
	_teardown()


## 4. Shard vs shard: os fragmentos continuam colidindo entre si
## (máscara própria bit 4) — não atravessam um ao outro.
func _case_shard_vs_shard() -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var left := _spawn_shard(STONE_SHARD_SCENE, Vector2(-150, 0), false)
	var right := _spawn_shard(STONE_SHARD_SCENE, Vector2(150, 0), false)
	left.linear_velocity = Vector2(250, 0)
	right.linear_velocity = Vector2(-250, 0)

	for i in 90:
		await physics_frame
		if not is_instance_valid(left) or not is_instance_valid(right):
			break

	_check(is_instance_valid(left) and is_instance_valid(right),
		"ambos os shards seguem válidos")
	if is_instance_valid(left) and is_instance_valid(right):
		_check(left.global_position.x < right.global_position.x,
			"shards não atravessaram um ao outro (esq=%.0f < dir=%.0f)" % [
				left.global_position.x, right.global_position.x])
		var touched := absf(left.linear_velocity.x - 250.0) > 1.0 \
			or absf(right.linear_velocity.x + 250.0) > 1.0
		_check(touched,
			"contato alterou as velocidades (esq.vx=%.0f dir.vx=%.0f)" % [
				left.linear_velocity.x, right.linear_velocity.x])
	_teardown()


## 5. Bala ainda colide no sólido do mundo: trava no contato (máscara 1
## da bala intacta, regra OR do motor).
func _case_bullet_hits_world() -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	_make_static_rect(Vector2(0, 0), Vector2(40, 2000))  # parede fina
	var bullet := await _spawn_bullet(Vector2(-200, 0), Vector2(600, 0), false)

	var blocked := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(bullet):
			blocked = true
			break
		if bullet.linear_velocity.x < 100.0:
			blocked = true
			break

	_check(blocked, "bala bloqueada/ricocheteou no sólido do mundo")
	if is_instance_valid(bullet):
		_check(bullet.global_position.x < -15.0,
			"bala parada antes de atravessar a parede (x=%.1f)" % bullet.global_position.x)
	_teardown()


## 6. Bala↔bala: colisão existente preservada (mask 3 recupera o bit 2
## das balas, que antes eram enxergadas pelo bit 1 da camada 1+2).
func _case_bullet_vs_bullet() -> void:
	_teardown()
	_world = Node2D.new()
	root.add_child(_world)

	var a := await _spawn_bullet(Vector2(-200, 0), Vector2(600, 0), false)
	var b := await _spawn_bullet(Vector2(200, 0), Vector2(-600, 0), false)

	for i in 60:
		await physics_frame
		if not is_instance_valid(a) or not is_instance_valid(b):
			break

	_check(is_instance_valid(a) and is_instance_valid(b),
		"ambas as balas seguem válidas")
	if is_instance_valid(a) and is_instance_valid(b):
		_check(a.global_position.x < b.global_position.x,
			"balas não atravessaram uma da outra (a=%.0f < b=%.0f)" % [
				a.global_position.x, b.global_position.x])
		var touched := absf(a.linear_velocity.x - 600.0) > 1.0 \
			or absf(b.linear_velocity.x + 600.0) > 1.0
		_check(touched,
			"contato alterou as velocidades (a.vx=%.0f b.vx=%.0f)" % [
				a.linear_velocity.x, b.linear_velocity.x])
	_teardown()


func _on_bullet_body_entered(body: Node2D) -> void:
	if body is Shard:
		_shard_contacts += 1


## Instancia um shard real com `lifetime` estendido (fixture: evita o
## auto-free de 3s do _ready durante as medições).
func _spawn_shard(scene: PackedScene, pos: Vector2, gravity_on: bool) -> RigidBody2D:
	var shard := scene.instantiate() as RigidBody2D
	shard.lifetime = 60.0
	shard.gravity_scale = 1.0 if gravity_on else 0.0
	shard.position = pos
	_world.add_child(shard)
	return shard


## Bala real (escala canônica 0.16) no padrão dos testes da bala:
## pose/velocidade ANTES do add (deferred) para o _ready nascer na posição.
func _spawn_bullet(pos: Vector2, vel: Vector2, gravity_on: bool) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = pos
	bullet.gravity_scale = 1.0 if gravity_on else 0.0
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = vel
	_world.add_child.call_deferred(bullet)
	await physics_frame
	return bullet


## StaticBody2D retangular puro (padrão stone_impact_test.gd).
func _make_static_rect(pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	body.add_child(col)
	body.position = pos
	_world.add_child(body)
	return body


func _teardown() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		_world = null
	for trail in get_nodes_in_group("bullet_trails"):
		(trail as Node).queue_free()
	await physics_frame
