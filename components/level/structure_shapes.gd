class_name StructureShapes extends RefCounted
## Posicionamento de Structures (docs/plan.md, Etapa 4).
## EXECUTA o papel declarado pela composição — não tapa vão, não decide:
## sem RNG, sem validação. `beam` liga dois elementos (link_a/link_b);
## `support` leva carga de um elemento ao Floor. A validação confere
## depois se cada papel existe geometricamente (reprova sem corrigir).
## Escala dos guides: 0.15 (~72x67px). Rotação: 90 = viga horizontal,
## 0 = coluna/suporte (convenção dos guides).

const SCALE := Vector2(0.15, 0.15)


## Viga entre dois pontos (extremidades declaradas via links).
## Horizontal => 90°, vertical => 0°.
static func beam(id: String, a: Vector2, b: Vector2, link_a: String, link_b: String) -> StructureDefinition:
	var struct := StructureDefinition.new()
	struct.id = id
	struct.position = (a + b) * 0.5
	struct.rotation_degrees = 90.0 if absf(b.x - a.x) >= absf(b.y - a.y) else 0.0
	struct.scale = SCALE
	struct.role = StructureDefinition.ROLE_BEAM
	struct.link_a = link_a
	struct.link_b = link_b
	return struct


## Suporte vertical num ponto, levando carga de `link` ao Floor.
static func support(id: String, at: Vector2, link: String) -> StructureDefinition:
	var struct := StructureDefinition.new()
	struct.id = id
	struct.position = at
	struct.rotation_degrees = 0.0
	struct.scale = SCALE
	struct.role = StructureDefinition.ROLE_SUPPORT
	struct.link_a = link
	struct.link_b = ""
	return struct
