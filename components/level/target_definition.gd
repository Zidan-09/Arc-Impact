class_name TargetDefinition extends Resource
## Posição e tamanho do alvo em forma de dados puros
## (Etapa 1, docs/plan.md §4.3). O tamanho é FIXO na v1.

const DEFAULT_SIZE := Vector2(80, 80) # espelha components/target/target.tscn

@export var position: Vector2 = Vector2(1000, 360)
@export var size: Vector2 = DEFAULT_SIZE


func to_dict() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"size": {"x": size.x, "y": size.y},
	}


static func from_dict(data: Dictionary) -> TargetDefinition:
	var def := TargetDefinition.new()
	var pos: Dictionary = data.get("position", {"x": 1000.0, "y": 360.0})
	def.position = Vector2(float(pos.get("x", 1000.0)), float(pos.get("y", 360.0)))
	var siz: Dictionary = data.get("size", {"x": DEFAULT_SIZE.x, "y": DEFAULT_SIZE.y})
	def.size = Vector2(float(siz.get("x", DEFAULT_SIZE.x)), float(siz.get("y", DEFAULT_SIZE.y)))
	return def
