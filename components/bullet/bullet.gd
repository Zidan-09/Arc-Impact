class_name Bullet
extends RigidBody2D
## Projétil do canhão — fonte única de verdade (docs/plan.md §5 item 2):
## - Corpo: CircleShape2D raio 57.717 (valor-base em `bullet.tscn`;
##   x escala canônica 0.16 do canhão = ~9.2px, o calibre calibrado;
##   `apply_cannon_scale()` o reescala por instância sem mutar o recurso).
## - collision_layer/mask: 2/3. O mask 3 = mundo (bit 1, igual ao antigo
##   mask 1) + balas (bit 2): é a mask que os rays/CCD usam e mantém o
##   MESMO conjunto visível de antes (as balas estavam na camada 1+2 e
##   eram enxergadas pelo bit 1 — agora estão só na 2, e o bit 2 do mask
##   recupera a colisão bala↔bala). O layer 2 é o bit "pode ser atraído",
##   lido só pelo `collision_mask` das Areas2D do Target. A bala SAIU da
##   camada 1 ("mundo") para o isolamento Bullet↔Shards: os shards estão
##   na camada 4 (layer 8) com mask 1+4, então o mask 1 deles não enxerga
##   mais a bala (que saiu da camada 1) e o mask 3 da bala não enxerga o
##   layer 8. A colisão corpo-corpo do motor é OR (basta UMA direção
##   casar): bala↔mundo segue intocado pela direção "mask da bala & layer
##   do mundo", e bala↔shard morre nas DUAS direções. As Areas2D com
##   mask 1 que detectavam a bala pela camada 1 — BulletReturnDetector
##   (cannon.tscn) e HitBox do vidro (glassObstacle.tscn) — passaram a
##   mask 3 (bit 2 da bala), pois a detecção de Area2D é direcional (só
##   area.mask & body.layer). O `Target` não tem mais shape — a bala o
##   atravessa.
## - Lógica de gameplay (`Obstacle.hit()`) roteada AQUI; o alvo é
##   absorvido fora daqui, pelo `body_entered` da `AbsorptionArea`:
##   `body_entered` do corpo + varredura `intersect_ray` do segmento
##   prev→current com `collide_with_areas = true` (alcança o `HitBox`
##   Area2D do vidro mesmo quando o tick pula o collider fino).
## - Deduplicação por instância: o primeiro hit por corpo vale; o resto
##   é ignorado (idempotência soma com `is_processing_hit`/`is_broken`).
## - Vidro usa Area2D atravessável (atenua *= 0.85 em vez de rebater);
##   ver `glass_obstacle.gd`. Shards são ignorados pelos obstáculos.

var is_broken: bool = false

# Base capturada na primeira chamada (valor do bullet.tscn).
# Guardada para que apply_cannon_scale() nunca acumule fator.
var _base_body_radius: float = -1.0
var _base_sprite_scale: Vector2 = Vector2.ZERO

# Varredura do trecho a percorrer (item 2) + CCD preditivo: raio e
# shapecast cobrem o movimento que o motor VAI integrar neste tick, antes
# do passo. Teleporte de spawn (>120px/frame, ou >2 passos de velocidade)
# só realinha o cursor, sem varrer (evita falso positivo do add_child
# antes do posicionamento no muzzle — ver cannon.gd:shoot()).
var _prev_position: Vector2 = Vector2.INF
const TELEPORT_DIST := 120.0
const SWEEP_MAX_STEPS := 8

# CCD manual (shapecast) — por que não basta o motor:
# `continuous_cd` está habilitado na cena (modo cast shape), mas o
# GodotPhysics2D é INERTE aqui (medido: resultados idênticos com CCD
# ligado/desligado, mesmo em tile único a 20000 px/s). Sem isso,
# dois modos de falha:
#  1. Junção: um passo de integração a 2000 px/s (~33px) penetra além
#     do canto compartilhado entre dois StaticBody2D adjacentes; os
#     contatos passam a ser as faces LATERAIS opostas da fresta, cujas
#     normais se cancelam horizontalmente — nada empurra a bola para
#     cima e ela escorrega pela fresta (reproduzível: junção atravessa
#     a 1000 px/s, enquanto o centro de um tile aguenta 4000 px/s).
#  2. Alta velocidade: acima de ~6000 px/s a bola atravessa até um tile
#     ÚNICO (100px/passo > 64px+raio).
# A correção é PREDITIVA: a cada tick varremos o movimento que o motor
# VAI integrar (current + velocidade*dt) com o shape REAL da bala (raio
# já escalado) e interrompemos na POSE de primeiro contato ANTES do
# passo. Isso é essencial, não só otimização: a bala nunca chega a
# ficar DENTRO da fresta, porque
#  (a) é a sobreposição profunda no canto compartilhado que faz os
#      empuxos laterais dos dois tiles se cancelarem (o bug acima), e
#      (b) medimos que SAIR de sobreposição profunda via
#      `global_position` explode o CCD do motor: RigidBody2D puro
#      teleportado de dentro da junção para fora com continuous_cd=2
#      teve x=-283374 no passo seguinte (v_x=0; com CCD=0, limpo).
#      Contato raso/tocado nunca dispara isso.
# Dois comportamentos do motor medidos guiam o desenho:
#  - `intersect_shape` NÃO devolve `normal` (só collider/position): a
#    face de contato é derivada da geometria do retângulo atingido
#    (menor penetração, ver `_static_face_normal`); numa junção as
#    normais dos dois lados SOMAM => resposta de canto (ex.: 45°).
#  - `cast_motion` devolve [1,1] TAMBÉM quando o shape já COMEÇA
#    sobreposto (não sinaliza): a pose inicial é conferida contra os
#    sólidos para recuperar de sobreposição (ex.: velocity externa de
#    stone/target apontou a bala para dentro da parede).
# Após o contato raso, o ricochete (bounce/atrito dos PhysicsMaterial)
# é resolvido aqui com as mesmas fórmulas do motor, reproduzindo a
# resposta que o passo discreto perdia na fresta — a mesma no centro de
# um elemento, em qualquer junção e em canto (até CCD_MAX_CONTACTS
# contatos por passo). Shards e demais corpos dinâmicos são ignorados
# pelo filtro (hoje a bala os atravessa; nada disso muda).
const SOLID_SWEEP_EPSILON := 0.0001
# Passo mínimo para varrer: abaixo disso não existe sobreposição profunda
# possível (o motor resolve por empuxo), e o early-return de repouso
# (`dist < 0.01`) já cobre o caso.
const CCD_MIN_SWEEP_LEN := 0.5
# Pressão mínima (px do passo na direção da normal) para travar um corpo
# que já está tocando a superfície. Abaixo disso é repouso/deslize (sag
# da gravidade ~0,3px/tick) e o empuxo do motor resolve.
const CCD_PRESS_EPSILON := 0.5
# Máximo de contatos resolvidos por tick (canto: chão + parede no mesmo
# passo). Voo livre gasta 1.
const CCD_MAX_CONTACTS := 3
# Profundidade da sonda de normal (piso; escala com o passo via ×0.03):
# precisa vencer a folga conservativa do `cast_motion` (para antes do
# toque real; ~0.12px reto e >0.3px numa junção de canto, onde esconderia
# a segunda face) e entrar o suficiente no sólido para o `intersect_shape`
# devolver a face certa, sem ser grande o bastante para confundir canto.
# 0.05px fixo falhava (vazio); 0.2px fixo + folga medida no canto motivou
# a escala com o comprimento do passo.
const SOLID_PROBE_DEPTH := 0.2

# Instâncias já roteadas (corpo e/ou Area2D do vidro).
var _notified_ids := {}

# Frame de física do último texto criado por ESTA bala (dedup por
# evento: um disparo que atinge 2 elementos ao mesmo tempo — encontro
# de 2 obstáculos na junção — gera UMA onomatopeia, não duas).
var _last_impact_text_frame := -1

var trail: BulletTrail


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_prev_position = global_position
	trail = BulletTrail.new()
	trail.follow_target = self
	trail.add_to_group("bullet_trails")
	get_parent().add_child(trail)


## Ajusta o tamanho do bullet na mesma proporção do canhão.
## Por que explícito e não só `bullet.scale = ...`?
## Escalar um RigidBody2D via node.scale nem sempre propaga para a
## física (o servidor de física pode manter o raio original do
## CircleShape2D), então o visual encolhia mas a colisão continuava
## grande — e o bullet não saía do cano. Aqui o raio é alterado de
## fato (em shape duplicado por instância) mais o sprite.
## Massa e velocidade NÃO mudam: só geometria + visual.
func apply_cannon_scale(cannon_global_scale: Vector2) -> void:
	var factor := cannon_global_scale.x
	if absf(cannon_global_scale.x - cannon_global_scale.y) > 0.0001:
		push_warning(
			"Bullet.apply_cannon_scale: escala não-uniforme %s; usando x como fator." % str(cannon_global_scale)
		)

	if _base_body_radius < 0.0:
		# Lê o valor atual (instância recém-criada == valor do .tscn).
		_base_body_radius = (($CollisionShape2D as CollisionShape2D).shape as CircleShape2D).radius
		_base_sprite_scale = ($Sprite2D as Sprite2D).scale

	# Duplica o shape: o sub_resource do PackedScene é compartilhado
	# entre instâncias; sem duplicate() todas as balas seriam afetadas.
	var body_col := $CollisionShape2D as CollisionShape2D
	var body_circle := (body_col.shape as CircleShape2D).duplicate() as CircleShape2D
	body_circle.radius = _base_body_radius * factor
	body_col.shape = body_circle

	($Sprite2D as Sprite2D).scale = _base_sprite_scale * factor


func _physics_process(_delta: float) -> void:
	if is_broken:
		return
	if _prev_position == Vector2.INF:
		_prev_position = global_position
		return
	var current := global_position
	var dist := _prev_position.distance_to(current)
	if dist > maxf(TELEPORT_DIST, linear_velocity.length() * _delta * 2.0 + 8.0):
		# Spawn/teleporte: realinha sem varrer (posição do _ready é
		# anterior ao posicionamento no muzzle). O limiar cresce com a
		# velocidade para um voo rápido (>7200 px/s) não ser confundido
		# com teleporte (perderia o CCD em alta velocidade).
		_prev_position = current
		return
	# Movimento que o motor VAI integrar neste tick (medido: os callbacks
	# de nó rodam ANTES do passo de física — tests/order_probe.gd).
	var upcoming := (linear_velocity + get_gravity() * _delta) * _delta
	if dist < 0.01 and upcoming.length() < CCD_MIN_SWEEP_LEN:
		return
	# Roteia o trecho que a bala VAI percorrer: o clamp preditivo impede o
	# overlap físico com o sólido, então pedra/metal/vidro precisam ser
	# vistos pelo raio ANTES do CCD travar no contato (dedup por instância
	# garante hit() único; o corpo ainda sobrepõe glass/alvo, que seguem
	# pelo body_entered). O raio sozinho não cobre tudo: ele parte do
	# CENTRO da bala (o clamp mantém o centro ≥ raio da face, então em
	# baixa velocidade o passo/tick não alcança a superfície) e pára no
	# primeiro collider sem hit() de uma junção. O complemento é o
	# roteamento a partir do próprio contato do CCD (_route_contact_hits):
	# contato físico ⟺ impacto comunicado, exatamente 1x por bala/corpo.
	if upcoming.length() > 0.01:
		_swept_check(current, current + upcoming)
		upcoming = (linear_velocity + get_gravity() * _delta) * _delta
	# CCD manual preditivo: varre `upcoming` e trava na pose de primeiro
	# contato com o ricochete de material já aplicado. A bala nunca chega
	# a entrar na fresta/sólido: sem sobreposição profunda, sem a
	# recuperação por eixo de menor penetração que falhava na junção
	# (normais laterais se cancelando) e sem o salto posicional que o CCD
	# do motor emitia ao ser tirado de dentro de uma junção com
	# `global_position`.
	if upcoming.length() > CCD_MIN_SWEEP_LEN:
		# Até CCD_MAX_CONTACTS contatos por passo: no canto, a resposta
		# do primeiro contato (chão) aponta para a parede adjacente a
		# poucos px — sem a iteração a bala entraria nela no passo do
		# motor. Cada iteração extra custa 1 cast + 1 sonda, e só ocorre
		# em cantos/encostos (voo livre é 1 cast e sai).
		var remaining := upcoming
		for _i in CCD_MAX_CONTACTS:
			var hit := _sweep_against_solids(current, remaining)
			if hit.is_empty():
				break
			# Snapshot da velocidade de chegada: o ricochete usa a
			# velocidade que causou o contato (como o motor faria).
			var v_arrival := linear_velocity
			linear_velocity = _apply_solid_bounce(
				v_arrival, hit["normal"], hit["bounce"], hit["friction"]
			)
			# Roteia o impacto dos sólidos EFETIVAMENTE contatados DEPOIS
			# do ricochete: o clamp preditivo impede o overlap físico, o
			# `body_entered` não dispara mais para sólidos, e o raio de
			# `_swept_check` parte do centro (sempre ≥ raio da face pelo
			# próprio clamp) — sem este roteamento o CCD rebate a bala
			# sem comunicar o obstáculo (baixa velocidade: passo < raio;
			# junção: o raio pára no chão sem hit(); rasante no canto).
			# DEPOIS do bounce para hit() ver a velocidade pós-colisão
			# (o stone shatter reescreve 0.85× dela, como no body_entered).
			# Dedup por instância (_notified_ids) garante hit() único por
			# bala por corpo, idempotente com o raio/body_entered.
			_route_contact_hits(hit)
			current = hit["position"]
			remaining = (linear_velocity + get_gravity() * _delta) * _delta
			if remaining.length() <= CCD_MIN_SWEEP_LEN:
				break
	_prev_position = current
	global_position = current


## Varredura do trecho que a bala VAI percorrer no tick: enxerga bodies E
## areas (HitBox do vidro). Roteia o primeiro hit novo; vidro atravessável
## continua a varredura no mesmo segmento (pode haver alvo atrás).
func _swept_check(from: Vector2, to: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	var exclude: Array[RID] = [get_rid()]
	for _i in SWEEP_MAX_STEPS:
		var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, exclude)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit.get("collider")
		var pos: Vector2 = hit.get("position", to)
		if collider == null:
			break
		if not (collider is Node):
			break
		var node := collider as Node
		var id := node.get_instance_id()
		if _notified_ids.has(id):
			_exclude_collider(exclude, node)
			continue
		_notified_ids[id] = true
		print("[dbg-route] RAY node=%s pos=%s" % [node.name, pos])
		var routed := _route_hit(node, pos)
		if not routed:
			# Chão/parede sem hit(): física resolve; nada a rotear.
			break
		if is_broken:
			break
		if node is Area2D:
			# Vidro: atravessa com *= 0.85 — segue varrendo o resto
			# do segmento no mesmo tick (alvo atrás do vidro conta).
			_exclude_collider(exclude, node)
			continue
		# Sólido (pedra/metal/alvo): física rebate; encerra o tick.
		break


func _exclude_collider(exclude: Array[RID], node: Node) -> void:
	if node is CollisionObject2D:
		var rid := (node as CollisionObject2D).get_rid()
		if not exclude.has(rid):
			exclude.append(rid)


## CCD manual (shapecast) contra os SÓLIDOS do cenário. Varre o shape real
## da bala (raio já escalado) por `motion` a partir de `from`; se houver
## bloqueio, devolve a POSE de primeiro contato + normal + materiais do
## atingido (o caller aplica o ricochete e o clamp). Reproduz a resposta de
## ricochete/absorção que o passo discreto do motor perdia na fresta
## (normais laterais se cancelando), idêntica no centro de um elemento ou
## em qualquer junção. Só age sobre StaticBody2D da camada do mundo (chão,
## metal, pedra, parede do cano); vidro (Area2D) e shards/dinâmicos seguem
## como antes. Retorna {} quando o caminho está livre.
func _sweep_against_solids(from: Vector2, motion: Vector2) -> Dictionary:
	var motion_len := motion.length()
	if motion_len <= SOLID_SWEEP_EPSILON:
		return {}
	var space := get_world_2d().direct_space_state
	if space == null:
		return {}
	var col := $CollisionShape2D as CollisionShape2D
	if col == null or col.shape == null:
		return {}
	var dir := motion / motion_len

	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = col.shape
	var start_xf := global_transform
	start_xf.origin = from
	q.transform = start_xf
	q.motion = motion
	q.collision_mask = collision_mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [get_rid()]

	var res := space.cast_motion(q)
	if res.is_empty():
		return {}
	var safe := res[0]
	if safe >= 1.0:
		# Voo livre... mas `cast_motion` devolve [1,1] TAMBÉM quando o
		# shape já COMEÇA sobreposto ao sólido (medido: a bala voou de
		# dentro da parede direto), então a pose inicial é conferida.
		# Sem sobreposição => segue; com sobreposição (ex.: velocity
		# externa apontou para dentro) => trava na pose e reflete, e o
		# empuxo do motor ejeta (evita aprofundar/tunelar).
		q.transform = start_xf
		q.motion = Vector2.ZERO
		var start_hits := space.intersect_shape(q, 4)
		var start_solid := _probe_solids(start_hits, from, _bullet_radius())
		if start_solid.is_empty():
			return {}
		if -start_solid["normal"].dot(motion) < CCD_PRESS_EPSILON:
			# Só raspando/tangente ou saindo: deixa a física resolver.
			return {}
		return {
			"position": from,
			"normal": start_solid["normal"],
			"bounce": start_solid["bounce"],
			"friction": start_solid["friction"],
			"bodies": start_solid.get("bodies", []),
		}
	var contact := from + motion * safe

	# Sonda de normal: avança o shape além do ponto de parada para vencer
	# a folga conservadora do `cast_motion` (escala com o passo; 0.05px
	# fixo falhava, e numa junção de canto a folga passa de 0,3px e
	# escondia a segunda face) e obter a(s) face(s) certa(s).
	var probe_depth := maxf(SOLID_PROBE_DEPTH, motion_len * 0.03)
	var probe_center := contact + dir * probe_depth
	var probe_xf := global_transform
	probe_xf.origin = probe_center
	q.transform = probe_xf
	q.motion = Vector2.ZERO
	var hits := space.intersect_shape(q, 4)
	var probed := _probe_solids(hits, probe_center, _bullet_radius())
	if probed.is_empty():
		# Só shards/dinâmicos no caminho (ou fora de qualquer sólido):
		# deixa seguir; um sólido atrás será pego no próximo tick.
		return {}
	# Já tocando (safe<=0): só trava quando o movimento aperta para
	# DENTRO da superfície (ex.: resposta de ricochete que encaixaria a
	# bala na parede adjacente do canto no mesmo passo). Repouso/deslize
	# tem pressão só da sag da gravidade (< CCD_PRESS_EPSILON) e segue
	# com o empuxo do motor — travar aqui congelaria o deslize.
	if safe <= 0.0 and -probed["normal"].dot(motion) < CCD_PRESS_EPSILON:
		return {}
	return {
		"position": contact,
		"normal": probed["normal"],
		"bounce": probed["bounce"],
		"friction": probed["friction"],
		"bodies": probed["bodies"],
	}


## Raio real da bala (shape escalado por apply_cannon_scale).
func _bullet_radius() -> float:
	var col := $CollisionShape2D as CollisionShape2D
	if col != null and col.shape is CircleShape2D:
		return (col.shape as CircleShape2D).radius
	return 0.0


## Reduz os hits da sonda aos SÓLIDOS retangulares tocados e devolve
## {normal, bounce, friction, bodies} (vazio se nenhum). `intersect_shape`
## NÃO devolve `normal` (só collider/position), então a face de contato é
## derivada da geometria: menor profundidade de penetração face a face
## do retângulo (todos os sólidos do jogo são RectangleShape2D: chão,
## metal, pedra, parede do cano). Numa junção a sonda toca os dois
## lados e as normais SOMAM => resposta de canto (ex.: 45°). `bodies`
## lista os sólidos efetivamente tocados: é o que permite rotear o
## hit de gameplay a partir do contato do CCD (`_route_contact_hits`) —
## o clamp preditivo impede o overlap físico, então o contato do CCD é
## o sinal de impacto contra sólidos quando o raio do centro não
## alcança a face (baixa velocidade) ou para antes (junção).
func _probe_solids(hits: Array, probe_center: Vector2, radius: float) -> Dictionary:
	var normal := Vector2.ZERO
	var bounce := 0.0
	var friction := 1.0
	var got_material := false
	var bodies: Array = []
	for h in hits:
		var c: Object = h.get("collider")
		if not (c is StaticBody2D):
			# Vidro (Area2D) e shards/dinâmicos (RigidBody2D): ignorados
			# — a bala hoje os atravessa e nada disso muda.
			continue
		var hn := _static_face_normal(c as CollisionObject2D, probe_center, radius)
		if hn == Vector2.ZERO:
			# Sem face tocada (só passou perto): não é contato físico —
			# não soma normal nem entra no roteamento de gameplay.
			continue
		normal += hn
		if not bodies.has(c):
			bodies.append(c)
		if not got_material:
			var sm: PhysicsMaterial = (c as PhysicsBody2D).physics_material_override
			if sm != null:
				bounce = sm.bounce
				friction = sm.friction
				got_material = true
	if normal.length_squared() < 0.0001:
		return {}
	return {
		"normal": normal.normalized(),
		"bounce": bounce,
		"friction": friction,
		"bodies": bodies,
	}


## Normal da face de contato do círculo (raio `radius`, centro
## `probe_center`) contra os shapes retangulares de um StaticBody2D:
## face com menor profundidade de penetração, apontando para FORA do
## sólido. Funciona para o centro dentro ou fora do retângulo (rasgo).
## Retorna Vector2.ZERO se não há retângulo tocado (shapes não-ret
## ficam sem suporte; nenhum sólido do jogo é).
func _static_face_normal(body: CollisionObject2D, probe_center: Vector2, radius: float) -> Vector2:
	for owner_id in body.get_shape_owners():
		var shape := body.shape_owner_get_shape(owner_id, 0)
		if not (shape is RectangleShape2D):
			continue
		var xf := body.global_transform * body.shape_owner_get_transform(owner_id)
		# Eixo-alinhado na prática (o jogo não rotaciona sólidos); o
		# tamanho em mundo sai do comprimento das colunas da base.
		var half := Vector2(
			(shape as RectangleShape2D).size.x * 0.5 * xf.x.length(),
			(shape as RectangleShape2D).size.y * 0.5 * xf.y.length()
		)
		var left := (probe_center.x + radius) - (xf.origin.x - half.x)
		var right := (xf.origin.x + half.x) - (probe_center.x - radius)
		var top := (probe_center.y + radius) - (xf.origin.y - half.y)
		var bottom := (xf.origin.y + half.y) - (probe_center.y - radius)
		if left <= 0.0 or right <= 0.0 or top <= 0.0 or bottom <= 0.0:
			continue
		var dx := left if left < right else right
		var dy := top if top < bottom else bottom
		if dx < dy:
			return Vector2(-1.0 if left < right else 1.0, 0.0)
		return Vector2(0.0, -1.0 if top < bottom else 1.0)
	return Vector2.ZERO


## Resposta de contato no primeiro toque usando os MESMOS parâmetros de
## material do motor: restitution = max(bala, sólido), atrito = geométrico
## (regra de combinação de material do motor). Bala sem material => bounce 0 /
## atrito 1; chão (floor.tscn, physics_material_override) => bounce 0.7 /
## atrito 0 (ricocheete parcial: normal × 0.7, tangente preservada);
## metal/pedra => bounce 1 / atrito 0 (ricocheete pleno, |v| preservado);
## sólidos sem material (parede do cano etc.) => e=0, atrito 1 (absorve).
## Fórmula padrão de restituição: vn' = -e*vn; vt' = vt*(1-f). Pura:
## devolve a nova velocidade sem mutar nada, para o caller aplicar junto do
## clamp.
func _apply_solid_bounce(v: Vector2, normal: Vector2, s_bounce: float, s_fric: float) -> Vector2:
	var b_bounce := 0.0
	var b_fric := 1.0
	if physics_material_override != null:
		b_bounce = physics_material_override.bounce
		b_fric = physics_material_override.friction
	var e := maxf(b_bounce, s_bounce)
	var f := sqrt(b_fric * s_fric)
	var vn := v.dot(normal)
	if vn >= 0.0:
		# Já saindo da superfície (ou rasante): não reflete.
		return v
	var vt := v - normal * vn
	return vt * (1.0 - f) + normal * (-e * vn)


## Roteia o hit de gameplay para cada sólido contatado fisicamente no
## ponto de contato devolvido pelo CCD (clamp/ricochete ocorreu nele).
## Dedup por instância (_notified_ids) — a MESMA chave usada pelo raio
## de `_swept_check` e pelo `_on_body_entered`, garantindo exatamente
## 1 hit() por bala por corpo mesmo quando o raio já viu o sólido no
## mesmo tick. Chão/parede sem hit() são marcados e ignorados (mesmo
## comportamento do raio).
func _route_contact_hits(contact: Dictionary) -> void:
	var bodies = contact.get("bodies")
	if bodies == null:
		return
	var pos: Vector2 = contact.get("position", Vector2.ZERO)
	for body in bodies:
		if not (body is Node):
			continue
		var node := body as Node
		if not is_instance_valid(node):
			continue
		var id := node.get_instance_id()
		if _notified_ids.has(id):
			continue
		_notified_ids[id] = true
		print("[dbg-route] CCD node=%s pos=%s" % [node.name, pos])
		_route_hit(node, pos)


## Roteador único de gameplay. Retorna true se houve hit de gameplay.
## É TAMBÉM o ponto único de nascimento da onomatopeia de impacto
## (feature: Sistema de Onomatopeias nos Impactos): todo contato
## comunicado por aqui já passou pelo dedup por instância (os callers
## marcam o id em `_notified_ids` antes de chamar; o ramo de área
## confere o id do PAI, que é o elemento real do vidro), então cada
## elemento gera NO MÁXIMO UM texto — ricochete em rajada ou sinais
## duplicados não criam segunda onomatopeia. Além disso, um disparo
## que comunica 2 elementos no MESMO frame de física (encontro de 2
## obstáculos na junção) nasce UMA única onomatopeia: o dedup por
## frame mora em `_spawn_impact_text`. Cada chamada leva o MATERIAL do
## elemento (`_impact_material`), para o gerenciador sortear a palavra
## dentro do conjunto certo (TEXTS_BY_MATERIAL). Shards e o Target
## ficam de fora por requisito (ambos já eram ignorados pelo
## roteamento: o shard tem isolamento de camada e o Target não tem
## shape — a guarda explícita documenta e blindas a regra).
func _route_hit(node: Node, pos: Vector2) -> bool:
	if is_broken or not is_instance_valid(self):
		return false
	if node is Shard:
		return false
	if node is Target:
		return false
	if node.has_method("hit"):
		print("[dbg-route] has_hit node=%s pos=%s" % [node.name, pos])
		_spawn_impact_text(pos, _impact_material(node))
		node.call("hit", self, pos)
		return true
	if node is Area2D:
		# HitBox do vidro: o Area2D não tem hit(), o pai tem.
		var parent := node.get_parent()
		if parent != null and parent.has_method("hit"):
			var parent_id := parent.get_instance_id()
			# Dedup do ELEMENTO (não da área): se o caminho próprio do
			# vidro (sinal do HitBox -> route_external_hit) já processou
			# este impacto, não roteia de novo — nem hit() duplicado,
			# nem segundo texto.
			if _notified_ids.has(parent_id):
				return false
			_notified_ids[parent_id] = true
			print("[dbg-route] area_parent node=%s parent=%s pos=%s" % [
				node.name, parent.name, pos])
			_spawn_impact_text(pos, _impact_material(parent))
			parent.call("hit", self, pos)
			return true
		return false
	if node is StaticBody2D:
		# Chão/paredes do cenário: sem hit() (a física resolve o
		# ricochete, como sempre), mas é impacto válido — nasce a
		# onomatopeia (material `floor`). Balas (RigidBody2D) e shards
		# ficam fora.
		_spawn_impact_text(pos, _impact_material(node))
	return false


## Roteia um impacto detectado FORA dos caminhos internos da bala — o
## sinal próprio do HitBox do vidro (glass_obstacle.gd), que em
## contatos rasantes pode vencer a corrida do raio preditivo. Usa o
## MESMO dedup do roteador (`_notified_ids`, chave = instância do
## elemento): se a bala já comunicou o elemento, é no-op. Garante 1
## hit() e 1 onomatopeia por impacto, independentemente de qual caminho
## venceu. Chamado pela própria bala impactada.
func route_external_hit(element: Node, pos: Vector2) -> void:
	if is_broken or not is_instance_valid(self) or not is_instance_valid(element):
		return
	var id := element.get_instance_id()
	if _notified_ids.has(id):
		return
	_notified_ids[id] = true
	_route_hit(element, pos)


## Material do elemento atingido para a onomatopeia (chave de
## ImpactTextManager.TEXTS_BY_MATERIAL). O roteador já enxerga o nó:
## obstáculos são reconhecidos pela classe (Glass/Stone/Metal, todos
## subclasses de Obstacle), chão e paredes do cenário são StaticBody2D
## sem hit() => `floor`. Nó com hit() fora dessas classes (sondas de
## teste) cai em `floor` — fallback seguro, nunca bloqueia o texto.
## Material novo no jogo = 1 ramo aqui + 1 entrada em TEXTS_BY_MATERIAL.
func _impact_material(node: Node) -> StringName:
	if node is GlassObstacle:
		return ObstacleDefinition.KIND_GLASS
	if node is StoneObstacle:
		return ObstacleDefinition.KIND_STONE
	if node is MetalObstacle:
		return ObstacleDefinition.KIND_METAL
	return ImpactTextManager.KIND_FLOOR


## Ponto único de criação da onomatopeia: delega ao gerenciador
## central (limite rígido de 3 simultâneas, ver impact_text_manager.gd),
## que sorteia a palavra dentro do conjunto de `material`. Dedup por
## DISPARO e FRAME DE FÍSICA: um tiro que comunica 2 elementos no mesmo
## instante (encontro de 2 obstáculos na junção, contato CCD com bodies
## múltiplos) nasce UMA única onomatopeia — a gameplay (hit() de cada
## elemento) não muda. Frames distintos = impactos distintos = textos
## próprios (o limite de 3 continua valendo). Sem gerenciador na cena
## (ex.: tests/guides), é no-op.
func _spawn_impact_text(pos: Vector2, material: StringName) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _last_impact_text_frame:
		return
	var manager := ImpactTextManager.current
	if manager != null:
		_last_impact_text_frame = frame
		manager.spawn(pos, material)


func _on_body_entered(body: Node) -> void:
	if is_broken:
		return
	if body == null or not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	if _notified_ids.has(id):
		return
	_notified_ids[id] = true
	print("[dbg-route] BODY_ENTERED node=%s pos=%s" % [body.name, global_position])
	_route_hit(body, global_position)


func del_bullet():
	if is_broken:
		return

	is_broken = true

	queue_free()
