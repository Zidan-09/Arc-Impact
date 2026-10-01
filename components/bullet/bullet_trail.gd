class_name BulletTrail
extends Node2D

@export var trail_color := Color(0.66, 0.2, 1.0, 1.0)
@export var core_color := Color(0.85, 0.6, 1.0, 1.0)
@export var trail_width := 5.0
@export var glow_width_mult := 3.2
@export var glow_alpha := 0.28
@export var max_points := 48
@export var point_spacing := 8.0
@export var trail_lifetime := 10.0
@export var fade_time := 1.5
@export var light_energy := 0.7
@export var light_radius := 160.0

var follow_target: Node2D

var _core: Line2D
var _glow: Line2D
var _light: PointLight2D
var _age := 0.0
var _gone := false
var _fade_age := 0.0
var _gone_from := 1.0
var _trim_acc := 0.0
var _trim_rate := 0.0


func _ready() -> void:
	z_index = 1
	_glow = _make_line(trail_color, glow_alpha, trail_width * glow_width_mult)
	_core = _make_line(core_color, 1.0, trail_width)
	add_child(_glow)
	add_child(_core)
	_light = PointLight2D.new()
	_light.color = trail_color
	_light.energy = light_energy
	_light.texture = _make_light_texture()
	_light.texture_scale = light_radius / 64.0
	add_child(_light)


func _process(delta: float) -> void:
	if _gone:
		_update_gone(delta)
		return
	if not is_instance_valid(follow_target) or _age >= trail_lifetime:
		_begin_gone()
		return
	_age += delta
	_track()
	var fade_start := trail_lifetime - fade_time
	var alpha := 1.0
	if _age > fade_start:
		alpha = 1.0 - (_age - fade_start) / maxf(fade_time, 0.01)
	_apply_alpha(clampf(alpha, 0.0, 1.0))


func _track() -> void:
	var pos := to_local(follow_target.global_position)
	var count := _core.points.size()
	if count == 0:
		global_position = follow_target.global_position
		pos = Vector2.ZERO
		count = 0
	if count == 0 or _core.points[count - 1].distance_to(pos) >= point_spacing:
		_core.add_point(pos)
		_glow.add_point(pos)
		while _core.points.size() > max_points:
			_core.remove_point(0)
			_glow.remove_point(0)
	_light.position = pos


func _begin_gone() -> void:
	if _age >= trail_lifetime:
		queue_free()
		return
	_gone = true
	_fade_age = 0.0
	_gone_from = _core.modulate.a
	_trim_acc = 0.0
	_trim_rate = float(maxi(_core.points.size(), 1)) / maxf(fade_time, 0.01)


func _update_gone(delta: float) -> void:
	_age += delta
	if _age >= trail_lifetime:
		queue_free()
		return
	_fade_age += delta
	var left := _gone_from * (1.0 - _fade_age / maxf(fade_time, 0.01))
	_apply_alpha(maxf(left, 0.0))
	_trim_acc += _trim_rate * delta
	while _trim_acc >= 1.0 and _core.points.size() > 0:
		_core.remove_point(0)
		_glow.remove_point(0)
		_trim_acc -= 1.0
	if _fade_age >= fade_time or _core.points.size() < 2:
		queue_free()


func _apply_alpha(alpha: float) -> void:
	_core.modulate.a = alpha
	_glow.modulate.a = alpha
	_light.energy = light_energy * alpha


func _make_line(color: Color, head_alpha: float, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 0.0))
	gradient.set_color(1, Color(color.r, color.g, color.b, color.a * head_alpha))
	line.gradient = gradient
	return line


func _make_light_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture
