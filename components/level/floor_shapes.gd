class_name FloorShapes extends RefCounted
## Primitivas de execução do Floor (docs/plan.md, Etapa 4).
## CONVERTE a forma decidida pela composição em tiles — não decide nada:
## sem RNG, sem leitura de banda, sem validação. O CompositionBuilder
## escolhe o perfil (base + relevo); aqui só existe geometria exata na
## grade dos guides (tile 100x100 em scale 0.2, snap 50px como auxílio).
## Retorna arrays de FloorDefinition prontos para `def.floors`.

const TILE := 100.0
const BASE_Y := 670.0
const BASE_FROM_X := 50.0
const BASE_TO_X := 1250.0
const SCALE := Vector2(0.2, 0.2)


static func tile(x: float, y: float) -> FloorDefinition:
	var floor := FloorDefinition.new()
	floor.position = Vector2(x, y)
	floor.scale = SCALE
	return floor


## Faixa contínua cobrindo o piso (sempre presente, docs/Levels.md §2).
static func base() -> Array[FloorDefinition]:
	var out: Array[FloorDefinition] = []
	var x := BASE_FROM_X
	while x <= BASE_TO_X:
		out.append(tile(x, BASE_Y))
		x += TILE
	return out


## Patamar horizontal: `width_tiles` tiles centrados em `cx`, topo em
## `top_y` (centro dos tiles). Ex.: platform(200, 570, 2) => (150,570)
## + (250,570), o patamar do Guide1.
static func platform(cx: float, top_y: float, width_tiles: int) -> Array[FloorDefinition]:
	var out: Array[FloorDefinition] = []
	for i in maxi(width_tiles, 1):
		out.append(tile(cx + (float(i) - float(width_tiles - 1) * 0.5) * TILE, top_y))
	return out


## Coluna vertical portante em `x`, do topo `y_top` até `y_base`
## (padrão: a faixa base). Ex.: column(151, 164) => 6 tiles, a coluna
## do canhão do Guide2.
static func column(x: float, y_top: float, y_base: float = BASE_Y) -> Array[FloorDefinition]:
	var out: Array[FloorDefinition] = []
	var y := y_top
	while y <= y_base:
		out.append(tile(x, y))
		y += TILE
	return out


## Degraus entre dois níveis: `count` tiles subindo/descendo de
## (`x_start`, `y_start`) até (`x_end`, `y_end`), um degrau de 100px
## por tile. O ritmo (lado, largura) foi decidido pela composição.
static func steps(x_start: float, y_start: float, x_end: float, y_end: float, count: int) -> Array[FloorDefinition]:
	var out: Array[FloorDefinition] = []
	var n := maxi(count, 1)
	for i in n:
		var t := 0.0 if n == 1 else float(i) / float(n - 1)
		out.append(tile(lerpf(x_start, x_end, t), lerpf(y_start, y_end, t)))
	return out
