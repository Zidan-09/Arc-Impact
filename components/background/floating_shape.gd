class_name FloatingShape
extends RefCounted

const CIRCLE_SIDES := 0

var position := Vector2.ZERO
var velocity := Vector2.ZERO
var rotation := 0.0
var rotation_speed := 0.0
var radius := 24.0
var sides := 5
var color := Color(1.0, 1.0, 1.0, 0.15)
var sway_phase := 0.0
var sway_amplitude := 8.0
var sway_frequency := 0.5


func update(delta: float, area: Vector2, margin: float) -> void:
	position += velocity * delta
	rotation += rotation_speed * delta
	sway_phase += sway_frequency * delta
	var wrap_w := area.x + margin * 2.0
	var wrap_h := area.y + margin * 2.0
	if wrap_w > 0.0:
		if position.x < -margin:
			position.x += wrap_w
		elif position.x > area.x + margin:
			position.x -= wrap_w
	if wrap_h > 0.0:
		if position.y < -margin:
			position.y += wrap_h
		elif position.y > area.y + margin:
			position.y -= wrap_h


func draw_position() -> Vector2:
	if velocity.length_squared() <= 0.0001 or sway_amplitude <= 0.0:
		return position
	var perp := velocity.normalized().rotated(PI * 0.5)
	return position + perp * sin(sway_phase) * sway_amplitude


func is_circle() -> bool:
	return sides == CIRCLE_SIDES


func outline_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := maxi(sides, 3)
	for i in range(count):
		var angle := TAU * float(i) / float(count) - PI * 0.5
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
