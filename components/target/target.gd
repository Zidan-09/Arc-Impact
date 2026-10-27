class_name Target
extends StaticBody2D
## Alvo da fase — buraco negro. 3 sprites compostos: `base` (estática),
## `ring` e `portal`, que giram em sentidos opostos de forma infinita em
## `_process(delta)` (mesmo padrão do background: incremental, sem Tween
## e sem reinicialização perceptível).
##
## A raiz NÃO tem CollisionShape2D: a bala atravessa o alvo em vez de
## ricochear. A interação é feita só por duas Areas2D:
## - `GravityArea` (raio do `ring`) = horizonte de eventos: captura a bala
##   e redireciona o `linear_velocity` para o centro a cada physics tick,
##   curvando a trajetória e impedindo a fuga;
## - `AbsorptionArea` (raio do `portal`) = absorve: emite `target_hit`
##   (condição de vitória consumida por game.gd e cannon_controller.gd)
##   e libera a bala.
## Ambas usam `collision_mask` com o bit das balas, então enxergam apenas
## o que pode ser atraído — obstáculos e piso ficam fora.

signal target_hit(body: Bullet)

## Velocidade angular dos sprites animados (rad/s): 1 volta a cada ~6,3 s.
## Em Godot a rotação positiva é horária, por isso o `ring` (anti-horário)
## subtrai e o `portal` (horário) soma.
const SPIN_SPEED := 1.0

## Taxa exponencial da atração (1/s). `1 - exp(-rate * delta)` rende o
## mesmo resultado em qualquer FPS: em vez de teleportar a bala, o vetor
## velocidade GIRA na direção do centro — daí a trajetória curva.
## 30 => peso ~0,39/tick: no pior caso (bala ~2600 px/s entrando rasante
## na borda do `ring`) o passo de 33px ainda termina DENTRO do campo.
const PULL_RATE := 30.0

## Velocidade mínima imposta pelo campo (px/s). A lerp preserva a
## magnitude atual, então sem este piso uma bala lenta com a gravidade do
## projeto (980 px/s²) empurrando CONTRA o centro (alvo acima do canhão)
## equilibra num drift para fora e escapa. O déficit de equilíbrio é
## `gravity / PULL_RATE` (~33 px/s); 300 deixa ~267 px/s líquidos p/ dentro.
const MIN_PULL_SPEED := 300.0

@onready var ring: Sprite2D = $ring
@onready var portal: Sprite2D = $portal
@onready var gravity_area: Area2D = $GravityArea
@onready var absorption_area: Area2D = $AbsorptionArea


func _ready() -> void:
	absorption_area.body_entered.connect(_on_absorption_area_body_entered)


func _process(delta: float) -> void:
	ring.rotation -= SPIN_SPEED * delta
	portal.rotation += SPIN_SPEED * delta


## `get_overlapping_bodies()` já vem filtrado pelo `collision_mask` das
## balas e se auto-limpa — sem dicionário de capturados nem sinal de saída.
func _physics_process(delta: float) -> void:
	for body in gravity_area.get_overlapping_bodies():
		if body is Bullet:
			_attract(body as Bullet, delta)


## Redireciona `linear_velocity` gradualmente em direção ao centro.
## A magnitude não cai nunca (só GIRA o vetor), então o componente radial
## só passa a apontar para dentro: uma vez dentro do campo a distância ao
## centro diminui a cada tick e a fuga é geometricamente impossível.
func _attract(bullet: Bullet, delta: float) -> void:
	if not is_instance_valid(bullet) or bullet.is_broken:
		return
	var to_center := global_position - bullet.global_position
	var dist := to_center.length()
	if dist < 0.01:
		return
	var speed := maxf(bullet.linear_velocity.length(), MIN_PULL_SPEED)
	var desired := to_center * (speed / dist)
	var weight := 1.0 - exp(-PULL_RATE * delta)
	bullet.linear_velocity = bullet.linear_velocity.lerp(desired, weight)


func _on_absorption_area_body_entered(body: Node2D) -> void:
	if body is Bullet:
		_absorb(body as Bullet)


## Absorção: registra o acerto (vitória) e tira a bala de circulação.
## `del_bullet()` marca `is_broken` — zera `_physics_process` e
## `_route_hit` dela — e faz `queue_free()`, então ela sai da árvore no
## mesmo frame e deixa de colidir/interagir com qualquer coisa.
func _absorb(bullet: Bullet) -> void:
	if not is_instance_valid(bullet) or bullet.is_broken:
		return
	target_hit.emit(bullet)
	bullet.del_bullet()
