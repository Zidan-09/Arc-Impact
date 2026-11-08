class_name Shard
extends RigidBody2D

## Camadas de colisão (autoradas nas cenas glass_shard_*/stone_shard_*):
## layer 8 = camada 4, EXCLUSIVA dos fragmentos; mask 9 = cenário (bit 1)
## + shards (bit 4). É o que isola Bullet↔Shards nativamente: a mask 3
## da bala não enxerga o layer 8 e a mask 9 não enxerga o layer 2 da
## bala (colisão corpo-corpo é OR — precisa falhar nas duas direções),
## enquanto fragmento↔cenário (bit 1 em ambos) e fragmento↔fragmento
## (bit 4) seguem colidindo exatamente como antes. Não mudar sem ler o
## cabeçalho de bullet.gd.

@export var lifetime: float = 3.0


func _ready() -> void:
	# Elemento transitório da fase: o grupo "shards" é a única forma de
	# game.gd encontrar e remover os shards na troca de fase
	# (_clear_transient_elements). Sem ele, o shard sobreviveria à nova
	# fase como filho de Level e continuaria na física/colisão por até
	# `lifetime` segundos, interagindo com obstáculos e estruturas novos.
	add_to_group("shards")
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()


## Instancia um shard sob `parent` já com pose e velocidades aplicadas.
## Centraliza o bloco de add_child dos obstáculos (vidro/pedra): o
## add_child precisa acontecer fora do flush de física — quem chama é o
## método adiado de cada obstáculo, aqui só ocorre a materialização.
static func spawn(
	parent: Node,
	scene: PackedScene,
	position: Vector2,
	rotation: float,
	velocity: Vector2,
	angular_velocity: float
) -> RigidBody2D:
	var shard := scene.instantiate() as RigidBody2D
	parent.add_child(shard)
	shard.global_position = position
	shard.global_rotation = rotation
	shard.linear_velocity = velocity
	shard.angular_velocity = angular_velocity
	return shard
