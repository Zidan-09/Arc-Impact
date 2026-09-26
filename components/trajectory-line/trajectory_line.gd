extends Line2D

@export var preview_time: float = 0.35
@export var time_step: float = 1.0 / 60.0
@export var max_distance: float = 320.0
@export var dot_count: int = 7
@export var dot_radius: float = 6.0
@export var dot_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var flow_speed: float = 4.0
@export var fade_tail: bool = true

var _path_local: PackedVector2Array = PackedVector2Array()
var _anim: float = 0.0

func _ready() -> void:
	clear_points()
	width = 0.0

func update_trajectory(origin: Vector2, initial_velocity: Vector2, gravity: float) -> void:
	clear_points()
	_path_local.clear()
	var gravity_vec := Vector2(0.0, gravity)
	var t := 0.0
	while t <= preview_time:
		var global_pos := origin + initial_velocity * t + 0.5 * gravity_vec * t * t
		if max_distance > 0.0 and global_pos.distance_to(origin) > max_distance:
			break
		_path_local.append(to_local(global_pos))
		t += time_step
	queue_redraw()

func _process(delta: float) -> void:
	if _path_local.size() < 2:
		return
	_anim = fmod(_anim + delta * flow_speed, 1.0) if dot_count > 0 else 0.0
	queue_redraw()

func _draw() -> void:
	if _path_local.size() < 2 or dot_count <= 0:
		return
	var total := _path_local.size()
	var step := float(total - 1) / float(maxi(dot_count - 1, 1))
	for i in range(dot_count):
		var f_idx := float(i) * step + _anim * step
		if f_idx >= float(total - 1):
			f_idx = fmod(f_idx, float(total - 1))
		var idx := clampi(int(f_idx), 0, total - 1)
		var pos := _path_local[idx]
		var c := dot_color
		if fade_tail:
			c.a *= 1.0 - float(i) / float(dot_count) * 0.7
		draw_circle(pos, dot_radius, c)
