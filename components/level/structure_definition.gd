class_name StructureDefinition extends Resource
## Uma Structure em forma de dados puros (docs/plan.md, Etapa 1).
## Structures são elementos DO DESENHO (docs/Levels.md §§1/5): cada peça
## nasce com um papel declarado — `beam` liga dois elementos, `support`
## leva carga até o Floor ou outro elemento. Nenhum corretor automático
## insere structures; a validação só verifica as ligações declaradas.
## Cena: `components/structure/Structure.tscn` (Node2D + Sprite, v1 sem
## colisão — ver LevelValidator/D3). Escala dos guides: 0.15.
## Não instancia Nodes, não usa RNG, não roda física.

const ROLE_BEAM := &"beam"
const ROLE_SUPPORT := &"support"

@export var id: String = "" # "struct_01" (determinístico: índice no array)
@export var position: Vector2 = Vector2.ZERO
@export var rotation_degrees: float = 0.0 # 0 = coluna/suporte, 90 = viga
@export var scale: Vector2 = Vector2(0.15, 0.15)
@export var role: StringName = ROLE_BEAM
## Ids dos elementos ligados ("obs_01", "floor", ...). `support` usa só
## `link_a` (origem) e o destino é o Floor.
@export var link_a: String = ""
@export var link_b: String = ""


func to_dict() -> Dictionary:
	return {
		"id": id,
		"position": {"x": position.x, "y": position.y},
		"rotation_degrees": rotation_degrees,
		"scale": {"x": scale.x, "y": scale.y},
		"role": String(role),
		"link_a": link_a,
		"link_b": link_b,
	}


static func from_dict(data: Dictionary) -> StructureDefinition:
	var def := StructureDefinition.new()
	def.id = str(data.get("id", ""))
	var pos: Dictionary = data.get("position", {"x": 0.0, "y": 0.0})
	def.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	def.rotation_degrees = float(data.get("rotation_degrees", 0.0))
	var scl: Dictionary = data.get("scale", {"x": 0.15, "y": 0.15})
	def.scale = Vector2(float(scl.get("x", 0.15)), float(scl.get("y", 0.15)))
	def.role = StringName(str(data.get("role", ROLE_BEAM)))
	def.link_a = str(data.get("link_a", ""))
	def.link_b = str(data.get("link_b", ""))
	return def
