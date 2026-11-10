extends Control
## Mapa de progresso horizontal da tela Levels.
##
## As fases são infinitas, então a trilha tem uma extensão fixa grande
## (CAP_LEVELS, sempre à frente do avanço do jogador) e os nós existem
## por janela: só os visíveis + MARGIN_NODES de folga ficam na árvore.
## Ao rolar, quem sai da margem vai para um pool (com teto, o excedente
## é liberado) e quem entra é reutilizado/criado — custo O(1)
## amortizado por trecho rolado, suportando milhares de fases.

signal level_selected(level: int)
signal blocked_selected(level: int)

const LevelNode := preload("res://components/level-map/level_node.gd")
const LevelTrack := preload("res://components/level-map/level_track.gd")

## Distância horizontal entre os centros dos nós.
const SPACING := 170.0
## Tamanho do nó (área de toque; o disco desenhado fica menor).
const NODE_SIZE := Vector2(96.0, 96.0)
## Folga antes da fase 1 e depois da última fase da trilha.
const PADDING := 240.0
## Nós mantidos vivos além da área visível (evita nós "piscando" na
## borda durante a rolagem).
const MARGIN_NODES := 3
## Extensão mínima da trilha (em fases) e quanto dela fica bloqueada
## à frente do avanço do jogador.
const CAP_LEVELS := 10000
const LOOKAHEAD_LEVELS := 200
## Teto do pool: acima disso os nós distantes são realmente liberados.
const POOL_CAP := 40
## Altura da barra de rolagem neon (descontada da trilha).
const SCROLL_BAR_HEIGHT := 10.0

@onready var scroll: ScrollContainer = $Scroll
@onready var track: LevelTrack = $Scroll/Track

## Fase atual (última desbloqueada). 0 = `setup()` ainda não rodou.
var frontier := 0
## Última fase da trilha.
var last_level := 1

## Nós vivos por fase: int -> LevelNode.
var _nodes: Dictionary = {}
var _pool: Array = []
var _loaded_min := 0
var _loaded_max := -1


func _ready() -> void:
	scroll.get_h_scroll_bar().value_changed.connect(_on_scroll_changed)
	_style_scroll_bar()
	resized.connect(_on_size_changed)
	track.resized.connect(_on_track_size_changed)


## Prepara a trilha para uma sessão e a posiciona na região da fase
## atual. Assíncrono: `await map.setup(fase)`.
func setup(current_level: int) -> void:
	frontier = maxi(current_level, 1)
	last_level = maxi(frontier + LOOKAHEAD_LEVELS, CAP_LEVELS)
	_update_track_size()
	_refresh_window()
	# O tamanho novo da trilha só vale no layout do frame seguinte:
	# rolar antes disso seria reajustado para 0 pela barra. A árvore é
	# capturada ANTES do await: a tela pode ser trocada no meio (o nó sai
	# da árvore e `get_tree()` vira null — a troca de cena é deferida).
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	# Saiu da árvore durante a espera (cena trocada): não há mais o que
	# posicionar.
	if not is_inside_tree() or frontier <= 0:
		return
	focus_level(frontier)
	_refresh_window()


## Rola o mapa para centralizar a fase informada (abertura da tela na
## região da fase atual, sem percorrer as fases anteriores).
func focus_level(level: int) -> void:
	if frontier <= 0 or scroll.size.x <= 0.0:
		return
	var target := int(center_x(level) - scroll.size.x * 0.5)
	scroll.scroll_horizontal = clampi(target, 0, max_scroll())


## Posição horizontal (na trilha) do centro do nó da fase.
func center_x(level: int) -> float:
	return PADDING + float(level - 1) * SPACING


## Posição vertical (na trilha) do centro do nó da fase.
func center_y(level: int) -> float:
	var height := track.size.y
	if height <= 0.0:
		height = track.custom_minimum_size.y
	return height * 0.5 + y_offset(level)


## Rolagem máxima possível com a trilha atual.
func max_scroll() -> int:
	return maxi(int(_total_width() - scroll.size.x), 0)


## Variação vertical determinística (senos somados): o caminho nunca é
## uma linha perfeitamente reta e a mesma fase cai sempre na mesma
## altura, em qualquer sessão.
static func y_offset(level: int) -> float:
	var t := float(level)
	return sin(t * 0.9) * 20.0 + sin(t * 0.37 + 1.3) * 15.0 + sin(t * 2.3 + 0.7) * 5.0


func _total_width() -> float:
	return PADDING * 2.0 + float(maxi(last_level - 1, 0)) * SPACING


func _on_scroll_changed(_value: float) -> void:
	_refresh_window()


func _on_size_changed() -> void:
	if frontier <= 0:
		return
	_update_track_size()
	_refresh_window()


func _on_track_size_changed() -> void:
	if frontier <= 0:
		return
	_relayout()


## Calcula a janela de fases visíveis (com margem) e carrega o que
## entrou/saiu. Durante a rolagem só há trabalho quando uma borda da
## janela cruza um nó: O(1) amortizado.
func _refresh_window() -> void:
	if frontier <= 0:
		return
	var view := scroll.size.x
	if view <= 0.0:
		return
	var scroll_x := float(scroll.scroll_horizontal)
	var half := NODE_SIZE.x * 0.5
	var first := 1 + int(floor((scroll_x - half - PADDING) / SPACING))
	var last := 1 + int(ceil((scroll_x + view + half - PADDING) / SPACING))
	var want_min := clampi(first - MARGIN_NODES, 1, last_level)
	var want_max := clampi(last + MARGIN_NODES, 1, last_level)
	if want_max < want_min:
		return
	if want_min == _loaded_min and want_max == _loaded_max:
		return
	_apply_window(want_min, want_max)


func _apply_window(want_min: int, want_max: int) -> void:
	# Libera (para o pool) quem ficou distante da região visível.
	for level: int in _nodes.keys():
		if level < want_min or level > want_max:
			_release(_nodes[level])
			_nodes.erase(level)
	# Cria/reutiliza os nós da nova janela.
	for level in range(want_min, want_max + 1):
		if not _nodes.has(level):
			_nodes[level] = _create(level)
	_loaded_min = want_min
	_loaded_max = want_max
	_update_path()


func _create(level: int) -> LevelNode:
	var node: LevelNode
	if _pool.is_empty():
		node = LevelNode.new()
		node.activated.connect(_on_node_activated)
		node.blocked.connect(_on_node_blocked)
	else:
		node = _pool.pop_back()
	track.add_child(node)
	node.size = NODE_SIZE
	_place(node, level)
	node.setup(level, _state_for(level))
	return node


func _release(node: LevelNode) -> void:
	track.remove_child(node)
	if _pool.size() < POOL_CAP:
		_pool.append(node)
	else:
		# Teto do pool: o excedente sai da memória de verdade.
		node.queue_free()


func _place(node: LevelNode, level: int) -> void:
	node.position = Vector2(center_x(level), center_y(level)) - NODE_SIZE * 0.5


## Reposiciona os nós carregados (o centro vertical acompanha a altura
## da trilha) e atualiza o caminho.
func _relayout() -> void:
	for level: int in _nodes:
		_place(_nodes[level], level)
	_update_path()


## Passa os centros dos nós carregados ao trilho, que desenha o caminho
## orgânico entre eles (recortado pela área visível do ScrollContainer).
func _update_path() -> void:
	var points := PackedVector2Array()
	var first := _loaded_min
	var started := false
	for level in range(_loaded_min, _loaded_max + 1):
		if not _nodes.has(level):
			continue
		if not started:
			first = level
			started = true
		points.append(Vector2(center_x(level), center_y(level)))
	track.set_path(points, first, frontier)


func _update_track_size() -> void:
	# A barra horizontal existe sempre (trilha muito maior que a
	# viewport), então a trilha a desconta da própria altura.
	var available := scroll.size.y - SCROLL_BAR_HEIGHT
	track.custom_minimum_size = Vector2(_total_width(), maxi(available, 1.0))


func _state_for(level: int) -> int:
	if level > frontier:
		return LevelNode.State.LOCKED
	if level == frontier:
		return LevelNode.State.CURRENT
	return LevelNode.State.DONE


func _on_node_activated(level: int) -> void:
	# Dupla checagem de segurança: uma fase bloqueada nunca inicia,
	# mesmo que um nó emita ativação por engano.
	if level < 1 or level > frontier:
		blocked_selected.emit(level)
	else:
		level_selected.emit(level)


func _on_node_blocked(level: int) -> void:
	blocked_selected.emit(level)


## Barra de rolagem no clima neon do jogo (trilha escura, pega ciano →
## magenta no hover), com altura confortável para toque.
func _style_scroll_bar() -> void:
	var bar := scroll.get_h_scroll_bar()
	bar.custom_minimum_size = Vector2(0.0, SCROLL_BAR_HEIGHT)
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.05, 0.03, 0.09, 0.75)
	trough.set_corner_radius_all(5)
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = Color(0.133, 0.827, 0.933, 0.85)
	thumb.set_corner_radius_all(5)
	var thumb_hot := StyleBoxFlat.new()
	thumb_hot.bg_color = Color(0.851, 0.275, 0.937, 0.95)
	thumb_hot.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("scroll", trough)
	bar.add_theme_stylebox_override("grabber_area", thumb)
	bar.add_theme_stylebox_override("grabber_area_highlight", thumb_hot)
