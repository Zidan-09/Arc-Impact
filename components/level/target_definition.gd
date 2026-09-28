class_name TargetDefinition extends Resource
## Posição, rotação e função do alvo em forma de dados puros
## (docs/plan.md, Etapa 1). A rotação FAZ PARTE da composição: é
## escolhida pela função do alvo no desenho (fechar tiro rasteiro,
## orientar entrada, pedir arco/ricochete) — nunca sorteada às cegas.
## O tamanho é FIXO na v1.

const DEFAULT_SIZE := Vector2(80, 80) # espelha components/target/target.tscn

@export var position: Vector2 = Vector2(1000, 360)
@export var size: Vector2 = DEFAULT_SIZE
@export var rotation_degrees: float = 0.0
## Função no desenho (ver Composition.TARGET_*). `exception` marca o
## desafio especial fora da zona direita (docs/Levels.md §4).
@export var role: StringName = &"foot"
@export var exception: bool = false


func to_dict() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"size": {"x": size.x, "y": size.y},
		"rotation_degrees": rotation_degrees,
		"role": String(role),
		"exception": exception,
	}


static func from_dict(data: Dictionary) -> TargetDefinition:
	var def := TargetDefinition.new()
	var pos: Dictionary = data.get("position", {"x": 1000.0, "y": 360.0})
	def.position = Vector2(float(pos.get("x", 1000.0)), float(pos.get("y", 360.0)))
	var siz: Dictionary = data.get("size", {"x": DEFAULT_SIZE.x, "y": DEFAULT_SIZE.y})
	def.size = Vector2(float(siz.get("x", DEFAULT_SIZE.x)), float(siz.get("y", DEFAULT_SIZE.y)))
	# Compatibilidade: dicts v1 não têm rotação/função (alvo sempre neutro).
	def.rotation_degrees = float(data.get("rotation_degrees", 0.0))
	def.role = StringName(str(data.get("role", &"foot")))
	def.exception = bool(data.get("exception", false))
	return def
