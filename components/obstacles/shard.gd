class_name Shard
extends RigidBody2D

@export var lifetime: float = 3.0


func _ready() -> void:
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
