class_name FloorDefinition extends Resource
## Um tile do Floor em forma de dados puros (docs/plan.md, Etapa 1).
## O Floor é a base estrutural da fase (docs/Levels.md §2): a composição
## sempre inclui a faixa base cobrindo o piso mais o relevo que o desenho
## exigir (plataforma, degraus, coluna). Cada tile usa a cena
## `components/floor/floor.tscn` (StaticBody2D 500x500 => 100x100 em
## scale 0.2). Não instancia Nodes, não usa RNG, não roda física.

@export var position: Vector2 = Vector2.ZERO
@export var scale: Vector2 = Vector2(0.2, 0.2)


func to_dict() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"scale": {"x": scale.x, "y": scale.y},
	}


static func from_dict(data: Dictionary) -> FloorDefinition:
	var def := FloorDefinition.new()
	var pos: Dictionary = data.get("position", {"x": 0.0, "y": 0.0})
	def.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var scl: Dictionary = data.get("scale", {"x": 0.2, "y": 0.2})
	def.scale = Vector2(float(scl.get("x", 0.2)), float(scl.get("y", 0.2)))
	return def
