class_name Target
extends StaticBody2D

signal target_hit(body: Bullet)

@onready var activeTexture = $Active
@onready var inactiveTexture = $Inactive
@onready var arrow = $Arrow

const RECOIL_DISTANCE := 15.0
const RECOIL_BACK_TIME := 0.06
const RECOIL_RETURN_TIME := 0.12
const RECOIL_DIRECTION := Vector2.RIGHT
const ARROW_APPROACH_DISTANCE := 50.0
const ARROW_APPROACH_TIME := 0.5

var arrow_tween: Tween
var arrow_initial_position: Vector2

var recoil_tween: Tween
var initial_position: Vector2

var animation_played = false

func _ready() -> void:
	add_to_group("target")

	initial_position = position

	activeTexture.visible = false
	inactiveTexture.visible = true

	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 1.0
	physics_material_override = mat

	_arrow_animation()

func hit(bullet: Bullet, _impact_position: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(bullet):
		return
	target_hit.emit(bullet)

	if not animation_played:
		animation_played = true
		_play_animation()
		
		
func _play_animation():
	inactiveTexture.visible = false
	activeTexture.visible = true

	play_recoil()


func play_recoil() -> void:
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	else:
		# Re-ancora: a posição pode ter sido definida após o _ready
		# (SimulationWorld faz add_child antes de posicionar).
		initial_position = position

	position = initial_position

	var recoil_dir := Vector2.RIGHT.rotated(global_rotation)
	var recoil_global_position := global_position + recoil_dir * RECOIL_DISTANCE

	var recoil_position: Vector2 = (get_parent() as Node2D).to_local(recoil_global_position)

	recoil_tween = create_tween()

	recoil_tween.tween_property(
		self,
		"position",
		recoil_position,
		RECOIL_BACK_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	recoil_tween.tween_property(
		self,
		"position",
		initial_position,
		RECOIL_RETURN_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	recoil_tween.tween_callback(_restore_texture)


func _restore_texture() -> void:
	activeTexture.visible = false
	inactiveTexture.visible = true

func _arrow_animation():
	if arrow == null:
		return
	arrow_initial_position = arrow.position
	if arrow_tween and arrow_tween.is_valid():
		arrow_tween.kill()
	arrow_tween = create_tween().set_loops()
	arrow_tween.tween_property(arrow, "position", arrow_initial_position + Vector2.RIGHT * ARROW_APPROACH_DISTANCE, ARROW_APPROACH_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	arrow_tween.tween_property(arrow, "position", arrow_initial_position, ARROW_APPROACH_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
