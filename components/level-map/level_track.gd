extends Control
## Trilho do mapa de progresso: guarda os centros dos nós carregados e
## desenha o caminho orgânico entre eles — pequenas variações verticais
## das fases (LevelMap.y_offset) somadas a uma curvatura leve por
## trecho, para nunca virar uma linha perfeitamente reta.
##
## Fica dentro do ScrollContainer de propósito: o desenho é recortado
## pela área visível, então só os trechos carregados existem na tela.

## Amostras por trecho da curva (bezier quadrática).
const SEGMENTS := 10
const PATH_WIDTH := 4.0
const GLOW_WIDTH := 13.0
## Amplitude da curvatura leve de cada trecho.
const SAG_AMP := 13.0

const TRAVELED_COLOR := Color(0.133, 0.827, 0.933, 0.9)
const TRAVELED_GLOW := Color(0.133, 0.827, 0.933, 0.14)
const LOCKED_COLOR := Color(0.392, 0.455, 0.545, 0.5)
const LOCKED_GLOW := Color(0.392, 0.455, 0.545, 0.1)

## Fase mais alta já desbloqueada: determina a cor de cada trecho
## (percorrido até lá = ciano, resto = cinza).
var frontier_level := 1

var _points := PackedVector2Array()
var _first_level := 1


## Recebe os centros dos nós carregados, em ordem de fase, e redesenha.
func set_path(points: PackedVector2Array, first_level: int, frontier: int) -> void:
	_points = points
	_first_level = first_level
	frontier_level = frontier
	queue_redraw()


func _draw() -> void:
	if _points.size() < 2:
		return
	for i in range(_points.size() - 1):
		# Trecho ligando a fase `_first_level + i` à seguinte: percorrido
		# quando as duas extremidades já foram desbloqueadas.
		var traveled := _first_level + i + 1 <= frontier_level
		var color := TRAVELED_COLOR if traveled else LOCKED_COLOR
		var glow := TRAVELED_GLOW if traveled else LOCKED_GLOW
		var curve := _curve(_points[i], _points[i + 1], _sag_for(_first_level + i))
		draw_polyline(curve, glow, GLOW_WIDTH, true)
		draw_polyline(curve, color, PATH_WIDTH, true)


## Bezier quadrática de A a B com o ponto de controle deslocado na
## vertical: o traço serpenteia em vez de seguir reto.
static func _curve(a: Vector2, b: Vector2, sag: float) -> PackedVector2Array:
	var ctrl := (a + b) * 0.5 + Vector2(0.0, sag)
	var out := PackedVector2Array()
	out.resize(SEGMENTS + 1)
	for s in range(SEGMENTS + 1):
		var t := float(s) / float(SEGMENTS)
		out[s] = a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
	return out


## Curvatura determinística por trecho (mesmo trecho => mesma forma,
## sem RNG global e sem estado entre sessões).
static func _sag_for(level: int) -> float:
	return sin(float(level) * 0.73 + 0.4) * SAG_AMP
