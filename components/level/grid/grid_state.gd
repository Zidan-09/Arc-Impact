class_name GridState extends RefCounted
## Grade lógica discreta da fase.
##
## A fase é raciocinada como uma matriz `cols x rows` de células, cada
## célula com exatamente um conteúdo. A grade é LÓGICA: a posição física
## final dos Nodes é calculada por [method world_pos] e nunca deve ser
## confundida com o tamanho visual/físico do Node.
##
## Separação explícita entre layout lógico (aqui) e instanciação física
## (LevelBuilder, que lê LevelDefinition — ver GridLevelGenerator.to_def).

enum Cell {
	EMPTY,
	FLOOR,
	CANNON,
	TARGET,
	GLASS,
	STONE,
	METAL,
	STRUCTURE,
}

const PLAY_W := 1280.0
const PLAY_H := 720.0
## Tamanho da célula em px — FONTE ÚNICA de verdade dimensional da fase.
## Determina posição das células, tamanho visual, físico e de colisão de
## TODOS os elementos (Floor, Glass, Stone, Metal, Structure, Cannon,
## Target): cada cena foi ajustada para ocupar exatamente CELL_SIZE x
## CELL_SIZE na escala de instanciação, e todas as escalas derivam daqui
## via `cell_scale_for()`. Medido contra as artes reais: 128 comporta o
## giro completo do barril do canhão e a seta do alvo sem vazar.
const CELL_SIZE := 128.0

var cols: int = 13
var rows: int = 8
var cells: PackedInt32Array = PackedInt32Array()
## Arquétipo/desafio intencional desta grade (ver GridLevelGenerator).
var archetype: StringName = &"mixed"


func _init(p_cols: int = 13, p_rows: int = 8) -> void:
	cols = p_cols
	rows = p_rows
	archetype = &"mixed"
	cells.resize(cols * rows)
	cells.fill(Cell.EMPTY)


func idx(col: int, row: int) -> int:
	return row * cols + col


func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < cols and row >= 0 and row < rows


func get_cell(col: int, row: int) -> int:
	if not in_bounds(col, row):
		return -1
	return cells[idx(col, row)]


func set_cell(col: int, row: int, value: int) -> void:
	if in_bounds(col, row):
		cells[idx(col, row)] = value


func is_empty(col: int, row: int) -> bool:
	return get_cell(col, row) == Cell.EMPTY


func find_all(value: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in rows:
		for col in cols:
			if cells[idx(col, row)] == value:
				out.append(Vector2i(col, row))
	return out


func find_first(value: int) -> Vector2i:
	for row in rows:
		for col in cols:
			if cells[idx(col, row)] == value:
				return Vector2i(col, row)
	return Vector2i(-1, -1)


func count(value: int) -> int:
	var n := 0
	for v in cells:
		if v == value:
			n += 1
	return n


func count_obstacles() -> int:
	return count(Cell.GLASS) + count(Cell.STONE) + count(Cell.METAL)


static func is_obstacle(value: int) -> bool:
	return value == Cell.GLASS or value == Cell.STONE or value == Cell.METAL


## Origem (canto superior esquerdo) da grade em px, determinística a
## partir das dimensões: fase centralizada na viewport base 1280x720.
static func origin_for(p_cols: int, p_rows: int) -> Vector2:
	return Vector2(
		(PLAY_W - float(p_cols) * CELL_SIZE) * 0.5,
		(PLAY_H - float(p_rows) * CELL_SIZE) * 0.5)


## Retângulo exato da fase em px (usado pelos limites da câmera).
func phase_bounds() -> Rect2:
	return Rect2(origin_for(cols, rows), Vector2(cols, rows) * CELL_SIZE)


## Escala que faz um conteúdo de `base_size` px ocupar exatamente uma
## célula (por eixo — artes não-quadradas recebem ajuste sub-pixel
## invisível em vez de sobra dimensional).
static func cell_scale_for(base_size: Vector2) -> Vector2:
	return Vector2(CELL_SIZE / base_size.x, CELL_SIZE / base_size.y)


## Centro mundial da célula (lógica -> física). Células quadradas de
## CELL_SIZE: vizinhas se encostam exatamente, sem sobreposição nem vão.
func world_pos(col: int, row: int) -> Vector2:
	var origin := origin_for(cols, rows)
	return origin + (Vector2(col, row) + Vector2(0.5, 0.5)) * CELL_SIZE


## Altura do relevo do Floor numa coluna: quantas células de Floor
## empilhadas acima da linha de base.
func floor_height_at(col: int) -> int:
	if col < 0 or col >= cols:
		return 0
	var h := 0
	var row := rows - 1
	while row >= 0 and get_cell(col, row) == Cell.FLOOR:
		h += 1
		row -= 1
	return h - 1 # desconta a linha de base


## Linha (row) do topo do Floor numa coluna, ou -1 sem Floor.
func floor_top_row_at(col: int) -> int:
	for row in rows:
		if get_cell(col, row) == Cell.FLOOR:
			return row
	return -1


## Representação textual para debug: qual célula contém qual elemento.
func to_ascii() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for row in rows:
		var line := ""
		for col in cols:
			line += _glyph(cells[idx(col, row)])
		lines.append(line)
	return "\n".join(lines)


func _glyph(value: int) -> String:
	match value:
		Cell.EMPTY:
			return "."
		Cell.FLOOR:
			return "#"
		Cell.CANNON:
			return "C"
		Cell.TARGET:
			return "T"
		Cell.GLASS:
			return "g"
		Cell.STONE:
			return "s"
		Cell.METAL:
			return "m"
		Cell.STRUCTURE:
			return "+"
	return "?"
