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
	if not is_instance_valid(follow_target):
		return
	var gpos: Vector2 = (follow_target as Node2D).global_position
	var count := _core.points.size()
	if count == 0:
		global_position = gpos
		_add_point(gpos)
		_light.position = Vector2.ZERO
		return
	var last_global := to_global(_core.points[count - 1])
	if last_global.distance_to(gpos) < point_spacing:
		_light.position = to_local(gpos)
		return
	# Clipe anti-travessia (só visual; gameplay intacto): o centro da bala
	# pode penetrar ~1 tick no sólido antes do rebote, e sem clipe a linha
	# entra no colisor (docs/images/trail*.png). Areas NÃO clipam: o vidro
	# atravessa por mecânica (*= 0.85) e o rastro deve cruzá-lo.
	var clip := _clip_segment(last_global, gpos)
	if bool(clip["has_surface"]):
		var surface: Vector2 = clip["surface"]
		if to_local(surface).distance_to(_core.points[_core.points.size() - 1]) > 0.5:
			_add_point(surface)
	if not bool(clip["end_inside"]):
		_add_point(gpos)
	_light.position = to_local(gpos)


func _add_point(g: Vector2) -> void:
	var pos := to_local(g)
	_core.add_point(pos)
	_glow.add_point(pos)
	while _core.points.size() > max_points:
		_core.remove_point(0)
		_glow.remove_point(0)


## Primeira face de BODY no segmento + se o centro final está dentro de
## um sólido. Retorna {"has_surface": bool, "surface": Vector2,
## "end_inside": bool}. Exclui a própria bala e shards (visuais, a bala
## os atravessa sem interagir).
func _clip_segment(from: Vector2, to: Vector2) -> Dictionary:
	var out := {"has_surface": false, "surface": Vector2.ZERO, "end_inside": false}
	var world := get_world_2d()
	if world == null:
		return out
	var space := world.direct_space_state
	if space == null:
		return out
	var mask := 0xFFFFFFFF
	if follow_target is CollisionObject2D:
		mask = (follow_target as CollisionObject2D).collision_mask
	var exclude := _query_exclude()
	var ray := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	for _i in 6:
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		if collider is Shard:
			exclude.append((collider as CollisionObject2D).get_rid())
			ray.exclude = exclude
			continue
		if collider is CollisionObject2D:
			out["has_surface"] = true
			out["surface"] = hit["position"]
		break
	var point := PhysicsPointQueryParameters2D.new()
	point.position = to
	point.collide_with_areas = false
	point.collide_with_bodies = true
	point.collision_mask = mask
	point.exclude = exclude
	for _i in 6:
		var found := space.intersect_point(point, 1)
		if found.is_empty():
			break
		var inner: Object = found[0]["collider"]
		if inner is Shard:
			exclude.append((inner as CollisionObject2D).get_rid())
			point.exclude = exclude
			continue
		out["end_inside"] = true
		break
	return out


func _query_exclude() -> Array[RID]:
	var exclude: Array[RID] = []
	if is_instance_valid(follow_target) and follow_target is CollisionObject2D:
		exclude.append((follow_target as CollisionObject2D).get_rid())
	# Outras balas em voo: o rastro nunca clipa nelas (são transitórias;
	# colisão bala↔bala, se ocorrer, é resolvida pela física).
	for node in get_tree().get_nodes_in_group("bullets"):
		if node != follow_target and node is CollisionObject2D and is_instance_valid(node):
			var rid := (node as CollisionObject2D).get_rid()
			if not exclude.has(rid):
				exclude.append(rid)
	return exclude


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
