class_name Cannon
extends Node2D

@export_range(-20.0, 90.0, 1.0)
var min_angle: float = -20.0

@export_range(-45.0, 83.0, 1.0)
var max_angle: float = 83.0

@export
var rotation_sensitivity: float = 0.5

@export var bullet_scene: PackedScene

@export var bullet_container: Node

@export var base_shot_speed: float = 1000.0

@onready var barrel_pivot: Node2D = $BarrelPivot
@onready var muzzle: Marker2D = $BarrelPivot/Muzzle
@onready var trajectory_line: Line2D = $BarrelPivot/Muzzle/TrajectoryLine

var recoil_tween: Tween
var barrel_initial_position: Vector2

const PIVOT_OFFSET := Vector2(-2, 0)
const MUZZLE_OFFSET := Vector2(267, -48)

## Escala canônica do canhão no jogo (fonte única, usada pelo gerador).
## Com ela, o giro completo do barril cabe na célula de 128px e a bala
## mantém o tamanho calibrado.
const CANNON_SCALE := Vector2(0.16, 0.16)

## Queda vertical (px locais, antes da escala) da origem do canhão até o
## ponto de apoio do pé. A cena compõe a base com o fundo exatamente no
## fundo da célula, então o pé fica a meia célula abaixo da origem:
## 400 x 0.16 = 64px = CELL_SIZE / 2 (ver GridState.CELL_SIZE).
const FOOT_DROP := 400.0

const RECOIL_DISTANCE := 25.0
const RECOIL_BACK_TIME := 0.06
const RECOIL_RETURN_TIME := 0.12

var current_angle: float = 45.0
var current_power: float = 1.0

@onready var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready() -> void:
	barrel_initial_position = barrel_pivot.position
	update_cannon_rotation()

func _process(_delta: float) -> void:
	if not is_instance_valid(trajectory_line):
		return
	if not trajectory_line.visible:
		return
	update_trajectory_preview(current_power)
		
func update_trajectory_preview(power: float = -1.0) -> void:
	if power < 0.0:
		power = current_power
	var muzzle_state := get_muzzle_state()
	var origin: Vector2 = muzzle_state["origin"]
	var direction: Vector2 = muzzle_state["direction"]
	
	var initial_velocity := direction * base_shot_speed * clampf(power, 0.0, 1.0)
	
	trajectory_line.update_trajectory(origin, initial_velocity, gravity)
	
func rotate_cannon(delta_y: float) -> void:
	current_angle += delta_y * rotation_sensitivity

	current_angle = clampf(
		current_angle,
		min_angle,
		max_angle
	)

	update_cannon_rotation()
	update_trajectory_preview(current_power)

func set_power(value: float) -> void:
	current_power = value
	update_trajectory_preview(current_power)

func update_cannon_rotation() -> void:
	barrel_pivot.rotation_degrees = -current_angle

static func muzzle_state_for(cannon_position: Vector2, angle_degrees: float) -> Dictionary:
	var rotation := deg_to_rad(-angle_degrees)
	return {
		"origin": cannon_position + PIVOT_OFFSET + MUZZLE_OFFSET.rotated(rotation),
		"direction": Vector2.RIGHT.rotated(rotation),
	}


## Ponto do pé do canhão em coordenadas de mundo (para o validador
## estrutural conferir o apoio no Floor). `cannon_scale` é a escala
## global do nó do canhão (0.2 no jogo, 0.3 nos guides).
static func foot_position(cannon_position: Vector2, cannon_scale: Vector2) -> Vector2:
	return cannon_position + Vector2(0, FOOT_DROP * cannon_scale.y)

func get_muzzle_state() -> Dictionary:
	return {
		"origin": muzzle.global_position,
		"direction": Vector2.RIGHT.rotated(muzzle.global_rotation),
	}

func get_spawn_parent() -> Node:
	if is_instance_valid(bullet_container):
		return bullet_container
	return get_tree().current_scene


func shoot(power: float = 1.0) -> void:
	if bullet_scene == null:
		push_warning("Cannon.shoot() sem bullet_scene definida.")
		return

	if is_instance_valid(trajectory_line):
		trajectory_line.visible = false

	play_recoil()

	var bullet := bullet_scene.instantiate() as Bullet

	get_spawn_parent().add_child(bullet)
	
	bullet.add_to_group("bullets")

	bullet.apply_cannon_scale(global_scale)

	var muzzle_state := get_muzzle_state()
	bullet.global_position = muzzle_state["origin"]

	var direction: Vector2 = muzzle_state["direction"]
	bullet.linear_velocity = direction * base_shot_speed * clampf(power, 0.0, 1.0)

func play_recoil() -> void:
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()

	barrel_pivot.position = barrel_initial_position

	var forward_direction := Vector2.RIGHT.rotated(
		barrel_pivot.global_rotation
	).normalized()

	var recoil_global_position := barrel_pivot.global_position - (
		forward_direction * RECOIL_DISTANCE
	)

	var recoil_position := barrel_pivot.to_global(
		barrel_pivot.position
	)

	recoil_position = barrel_pivot.get_parent().to_local(
		recoil_global_position
	)

	recoil_tween = create_tween()

	recoil_tween.tween_property(
		barrel_pivot,
		"position",
		recoil_position,
		RECOIL_BACK_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	recoil_tween.tween_property(
		barrel_pivot,
		"position",
		barrel_initial_position,
		RECOIL_RETURN_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
