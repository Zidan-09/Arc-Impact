class_name ObstacleDefinition extends Resource
## Um obstáculo da fase em forma de dados puros (Etapa 1, docs/plan.md §4.2).
## HP e física vêm do tipo (vidro 1HP atravessável, pedra 2HP, metal
## indestrutível) — ver `components/level/material_rules.gd` (Etapa 2).
## Não instancia Nodes, não usa RNG, não roda física.

const KIND_GLASS := &"glass"
const KIND_METAL := &"metal"
const KIND_STONE := &"stone"

@export var id: String = "" # "obs_01" (determinístico: índice no array)
@export var kind: StringName = KIND_GLASS
@export var position: Vector2 = Vector2.ZERO
@export var rotation_degrees: float = 0.0 # v1: só 0 ou 90
@export var scale: Vector2 = Vector2(0.2, 0.2)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": String(kind),
		"position": {"x": position.x, "y": position.y},
		"rotation_degrees": rotation_degrees,
		"scale": {"x": scale.x, "y": scale.y},
	}


static func from_dict(data: Dictionary) -> ObstacleDefinition:
	var def := ObstacleDefinition.new()
	def.id = str(data.get("id", ""))
	def.kind = StringName(str(data.get("kind", KIND_GLASS)))
	var pos: Dictionary = data.get("position", {"x": 0.0, "y": 0.0})
	def.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	def.rotation_degrees = float(data.get("rotation_degrees", 0.0))
	var scl: Dictionary = data.get("scale", {"x": 0.2, "y": 0.2})
	def.scale = Vector2(float(scl.get("x", 0.2)), float(scl.get("y", 0.2)))
	return def
