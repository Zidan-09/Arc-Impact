class_name BackgroundShapes
extends Node2D

@export_range(0, 60, 1) var shape_count := 22
@export_range(0, 2, 1) var depth_layers := 2
@export var min_radius := 14.0
@export var max_radius := 46.0
@export var min_speed := 6.0
@export var max_speed := 22.0
@export var min_rotation_speed := -0.25
@export var max_rotation_speed := 0.25
@export var min_opacity := 0.05
@export var max_opacity := 0.25
@export var sway_amplitude := 8.0
@export var sway_frequency := 0.5
@export var wrap_margin := 64.0
@export var grid_jitter := 0.4
@export var seed_value := 12345
@export var palette: Array[Color] = [
	Color(0.35, 0.95, 1.0),
	Color(1.0, 0.35, 0.85),
	Color(0.55, 0.45, 1.0),
	Color(0.45, 1.0, 0.75),
]

const GEOMETRIES := [3, 4, 5, 6, 0]

var _shapes: Array[FloatingShape] = []
var _rng := RandomNumberGenerator.new()
var _area := Vector2.ZERO


func _ready() -> void:
	_rng.seed = seed_value
	_area = _resolve_area()
	if _area.x > 0.0 and _area.y > 0.0:
		_generate()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	_update_area()
	if _shapes.is_empty() and maxi(shape_count, 0) > 0 and _area.x > 0.0 and _area.y > 0.0:
		_generate()
	for shape in _shapes:
		shape.update(delta, _area, wrap_margin)
	queue_redraw()


func _draw() -> void:
	var layer_count := maxi(depth_layers, 1)
	for layer in range(layer_count):
		var layer_frac := float(layer + 1) / float(layer_count)
		for shape in _shapes:
			if _shape_layer(shape) != layer:
				continue
			var pos := shape.draw_position()
			var radius := shape.radius * layer_frac
			var tint := shape.color
			tint.a *= 0.5 + 0.5 * layer_frac
			if shape.is_circle():
				draw_arc(pos, radius, 0.0, TAU, 48, tint, 2.0, true)
			else:
				var points := PackedVector2Array()
				for point in shape.outline_points():
					points.append(pos + point.rotated(shape.rotation) * layer_frac)
				points.append(points[0])
				draw_polyline(points, tint, 2.0, true)


func _resolve_area() -> Vector2:
	var control := get_parent() as Control
	if control != null and control.size.x > 0.0 and control.size.y > 0.0:
		return control.size
	var viewport_size := get_viewport_rect().size
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		return viewport_size
	return _area if _area != Vector2.ZERO else Vector2(1280, 720)


func _update_area() -> void:
	var new_area := _resolve_area()
	if new_area.x <= 0.0 or new_area.y <= 0.0:
		return
	if _area != Vector2.ZERO and new_area != _area:
		var ratio := new_area / _area
		for shape in _shapes:
			shape.position *= ratio
	_area = new_area


func _generate() -> void:
	_shapes.clear()
	var count := maxi(shape_count, 0)
	if count == 0:
		return
	var cols := maxi(int(ceil(sqrt(float(count)))), 1)
	var rows := maxi(int(ceil(float(count) / float(cols))), 1)
	for i in range(count):
		var row := float(i / cols)
		var cell := Vector2(float(i % cols) / float(cols), row / float(rows))
		var jitter := Vector2(_rng.randf_range(-grid_jitter, grid_jitter), _rng.randf_range(-grid_jitter, grid_jitter))
		var cell_offset := Vector2(0.5 / float(cols), 0.5 / float(rows))
		var shape := FloatingShape.new()
		shape.position = (cell + cell_offset + jitter * cell_offset) * _area
		shape.velocity = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) * _rng.randf_range(min_speed, max_speed)
		shape.rotation = _rng.randf_range(0.0, TAU)
		shape.rotation_speed = _rng.randf_range(min_rotation_speed, max_rotation_speed)
		shape.radius = _rng.randf_range(min_radius, max_radius)
		shape.sides = GEOMETRIES[_rng.randi_range(0, GEOMETRIES.size() - 1)]
		shape.sway_phase = _rng.randf_range(0.0, TAU)
		shape.sway_amplitude = sway_amplitude * _rng.randf_range(0.5, 1.2)
		shape.sway_frequency = sway_frequency * _rng.randf_range(0.7, 1.3)
		var tint: Color = palette[_rng.randi_range(0, palette.size() - 1)] if not palette.is_empty() else Color.WHITE
		tint.a = _rng.randf_range(min_opacity, max_opacity)
		shape.color = tint
		_shapes.append(shape)


func _shape_layer(shape: FloatingShape) -> int:
	var layer_count := maxi(depth_layers, 1)
	if layer_count == 1:
		return 0
	var frac := inverse_lerp(min_radius, max_radius, shape.radius)
	return clampi(int(frac * float(layer_count)), 0, layer_count - 1)


func _on_viewport_size_changed() -> void:
	_update_area()
