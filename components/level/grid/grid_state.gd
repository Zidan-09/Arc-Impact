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
const FLOOR_Y := 670.0
const LEFT_X := 70.0
const RIGHT_X := 1210.0
const TOP_Y := 80.0

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


## Passo horizontal: col0 -> LEFT_X, última col -> RIGHT_X.
func step_x() -> float:
	if cols <= 1:
		return 0.0
	return (RIGHT_X - LEFT_X) / float(cols - 1)


## Passo vertical: última linha -> FLOOR_Y, linha0 -> TOP_Y.
func step_y() -> float:
	if rows <= 1:
		return 0.0
	return (FLOOR_Y - TOP_Y) / float(rows - 1)


## Centro mundial da célula (lógica -> física).
func world_pos(col: int, row: int) -> Vector2:
	return Vector2(LEFT_X + float(col) * step_x(), FLOOR_Y - float((rows - 1) - row) * step_y())


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
