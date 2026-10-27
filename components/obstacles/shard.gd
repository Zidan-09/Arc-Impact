class_name Shard
extends RigidBody2D

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
