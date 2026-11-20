class_name ScreenNavigator
extends Control
## Hub de navegação deslizante: `[Game] <- [Home] -> [Settings]`.
##
## - Um único `Background` global (em `BackgroundLayer`, fora do
##   `ScreenHost`) permanece estático; só os painéis deslizam.
## - Isolamento de câmera: o `GameCamera` vive no canvas padrão e
##   afetaria qualquer `Control` do mesmo canvas. Por isso Home e
##   Settings são embrulhados em `CanvasLayer`s próprios (imunes à
##   câmera) e o fundo global + `BlockInput` também vivem em camadas.
##   Só o `World` do Game fica no canvas padrão (é o único conteúdo
##   que a câmera deve enquadrar); o `UILayer` do Game já é imune.
## - Como o painel do Game se move e a câmera é filha dele, a posição
##   local da câmera é compensada em `-delta` durante slides e
##   resizes: o global dela fica fixo e o mundo desliza junto com o
##   painel. Processo da câmera congelado durante o slide.
## - Painéis fora da área visível ficam `visible=true` deslocados
##   (nunca `visible=false`): medição de layout quebraria escondida.
## - `Levels` fica FORA deste sistema (troca destrutiva via
##   `change_scene_to_file`, como antes). Voltar de Levels reconstrói
##   o Main do zero através de `start_target` / `start_level` (args
##   consumidos uma única vez no `_ready`).
## - Áudio (Autoloads) e saves não são tocados pela navegação.

## Painel Home (nunca liberado após criado).
const HOME_SCENE: PackedScene = preload("res://screens/home.tscn")
## Painel Game (lazy na 1ª navegação, depois persistente).
const GAME_SCENE: PackedScene = preload("res://screens/game.tscn")
## Painel Settings (nunca liberado após criado).
const SETTINGS_SCENE: PackedScene = preload("res://screens/settings.tscn")

## Posição de cada painel na grade espacial (só o eixo X é usado;
## `Vector2i` deixa `(0,±1)` vertical aberto para o futuro).
const GRID := {
	"home": Vector2i(0, 0),
	"game": Vector2i(-1, 0),
	"settings": Vector2i(1, 0),
}
## Camadas dos embrulhos (abaixo do UILayer do Game=10, acima do mundo).
const WRAP_LAYER := {"home": 5, "settings": 6}
## Duração do slide (s). Mesmo valor nos dois lados (ambos horizontais).
const SLIDE_DURATION := 0.38
const SLIDE_TRANS := Tween.TRANS_CUBIC
const SLIDE_EASE := Tween.EASE_IN_OUT

## Args de reconstrução Main <- Levels (consumidos e zerados no `_ready`).
## `start_target`: "home" | "game". `start_level`: 0 = progresso, N = fase.
static var start_target := "home"
static var start_level := 0

var _current := "home"
var _navigating := false
var _panels := {}
var _wraps := {}
var _tween: Tween = null

@onready var _host: Control = $ScreenHost
@onready var _block: Control = $BlockLayer/BlockInput


func _ready() -> void:
	var target := String(start_target) if GRID.has(String(start_target)) else "home"
	var lvl := int(start_level)
	start_target = "home"
	start_level = 0
	_current = target
	get_viewport().size_changed.connect(_on_size_changed)
	_block.visible = false
	_add_panel("home", HOME_SCENE)
	_add_panel("settings", SETTINGS_SCENE)
	if target == "game":
		_ensure_game()
		var g = _panels.get("game")
		if is_instance_valid(g) and g.has_method("enter"):
			await g.enter({"level": lvl})
	_layout_instant()


## Painel visível atual ("home" | "game" | "settings").
func get_current() -> String:
	return _current


## True durante o slide — telas/botões devem recusar input concorrente.
func is_navigating() -> bool:
	return _navigating


## Volta ao Home (único "voltar" do sistema atual, só eixo X).
func go_back() -> void:
	if _current != "home":
		navigate_to("home")


## Navegação interna com slide. Chamadas concorrentes são ignoradas
## (sem fila). `params` é repassado ao `enter()` do painel alvo
## (ex.: `{"level": N}` para o Game).
func navigate_to(id: String, params: Dictionary = {}) -> void:
	if not GRID.has(id):
		return
	if _navigating:
		return
	if get_tree().paused:
		return
	if id == _current:
		if id == "game" and int(params.get("level", 0)) > 0:
			var same = _panels.get("game")
			if is_instance_valid(same) and same.has_method("enter"):
				await same.enter(params)
		return
	_navigating = true
	_block.visible = true
	if id == "game":
		_ensure_game()
		# Posiciona o Game recém-criado no slot offscreen antes do enter.
		_layout_instant()
	var target = _panels.get(id)
	if not is_instance_valid(target):
		_navigating = false
		_block.visible = false
		return
	# A transição cobre o carregamento: o painel-alvo prepara seus
	# recursos ANTES do slide (sem tela incompleta se demorar).
	if target.has_method("enter"):
		await target.enter(params)
		if not is_instance_valid(target):
			_navigating = false
			_block.visible = false
			return
	var old = _panels.get(_current)
	# Congela a câmera do Game e compensa o movimento do painel (ver
	# doc da classe): global fixo => mundo desliza junto.
	var cam: Camera2D = null
	var cam_start := Vector2.ZERO
	var game = _panels.get("game")
	if is_instance_valid(game):
		cam = game.get_node_or_null("WorldArea/World/GameCamera") as Camera2D
		if cam != null:
			cam.set_process(false)
			cam_start = cam.position
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(SLIDE_TRANS).set_ease(SLIDE_EASE)
	var vp := get_viewport_rect().size
	for pid in _panels:
		var p = _panels[pid]
		if not is_instance_valid(p):
			continue
		var start_pos: Vector2 = (p as Control).position
		var end_pos := Vector2(GRID[pid] - GRID[id]) * vp
		_tween.tween_property(p, "position", end_pos, SLIDE_DURATION)
		for layer in _canvas_layers(p):
			_tween.tween_property(layer, "offset", end_pos, SLIDE_DURATION)
		var wrap = _wraps.get(pid)
		if wrap is CanvasLayer and int((wrap as CanvasLayer).layer) > 0:
			_tween.tween_property(wrap, "offset", end_pos, SLIDE_DURATION)
		if pid == "game" and cam != null:
			_tween.tween_property(cam, "position", cam_start - (end_pos - start_pos), SLIDE_DURATION)
	await _tween.finished
	_current = id
	if is_instance_valid(old) and old.has_method("exit"):
		old.exit()
	if is_instance_valid(cam):
		cam.set_process(true)
	# Recalcula por segurança (resize no meio do slide é raro, mas o
	# tween teria mirado o tamanho antigo).
	_layout_instant()
	if id == "game" and is_instance_valid(target) and target.has_method("refresh_camera_view"):
		# O enter rodou com o painel offscreen (WorldHitArea fora da
		# viewport): reenquadra a câmera com as medidas reais.
		target.refresh_camera_view()
	_block.visible = false
	_navigating = false


## Instancia o Game sob demanda (uma única vez por vida do Main).
## `panel_mode` é ligado ANTES do add (o `_ready` do Game roda no add):
## em modo painel o load fica a cargo do `enter()`, preservando o
## autoload standalone usado pelos testes.
func _ensure_game() -> void:
	if is_instance_valid(_panels.get("game")):
		return
	var inst: Control = GAME_SCENE.instantiate()
	inst.name = "Game"
	inst.set("panel_mode", true)
	_host.add_child(inst)
	_panels["game"] = inst
	_wraps["game"] = inst


## Home/Settings vão embrulhados em CanvasLayer próprio (isolamento
## de câmera, ver doc da classe). O Game fica direto no host (o World
## precisa da câmera; o UILayer interno já é imune).
func _add_panel(id: String, packed: PackedScene) -> void:
	if is_instance_valid(_panels.get(id)):
		return
	var inst: Control = packed.instantiate()
	inst.name = {"home": "Home", "settings": "Settings"}.get(id, id)
	var wrap_name := {"home": "HomeLayer", "settings": "SettingsLayer"}.get(id, id)
	var wrap := CanvasLayer.new()
	wrap.name = wrap_name
	wrap.layer = int(WRAP_LAYER.get(id, 5))
	_host.add_child(wrap)
	wrap.add_child(inst)
	inst.position = Vector2.ZERO
	_panels[id] = inst
	_wraps[id] = wrap
	_set_panel_pos(inst, Vector2(GRID[id] - GRID[_current]) * get_viewport_rect().size)


## Posiciona todos os painéis de uma vez (sem animação). Também
## realinha offsets de CanvasLayer internos e embrulhos, e mantém a
## câmera compensada (global fixo) quando o resize acontece fora de
## slide.
func _layout_instant() -> void:
	var vp := get_viewport_rect().size
	for pid in _panels:
		var p = _panels[pid]
		if is_instance_valid(p):
			_set_panel_pos(p, Vector2(GRID[pid] - GRID[_current]) * vp)
	if _current == "game":
		var game = _panels.get("game")
		if is_instance_valid(game) and game.has_method("refresh_camera_view"):
			game.refresh_camera_view()


func _set_panel_pos(panel: Control, pos: Vector2) -> void:
	var delta := pos - panel.position
	panel.position = pos
	for layer in _canvas_layers(panel):
		(layer as CanvasLayer).offset = pos
	var wrap = _wraps.get(_pid_of(panel))
	if wrap is CanvasLayer:
		(wrap as CanvasLayer).offset = pos
	if panel.name == "Game" and delta != Vector2.ZERO:
		var cam := panel.get_node_or_null("WorldArea/World/GameCamera") as Camera2D
		if cam != null:
			cam.position -= delta


## Id do painel ("home" | "game" | "settings") pelo nó.
func _pid_of(panel: Control) -> String:
	for pid in _panels:
		if _panels[pid] == panel:
			return String(pid)
	return ""


## Todos os CanvasLayer internos ao painel (ex.: UILayer do Game).
## Vivem em screen-space e ignoram `position` do painel — o `offset`
## acompanha para a UI deslizar junto com o mundo.
func _canvas_layers(node: Node) -> Array:
	var out := []
	for c in node.get_children():
		if c is CanvasLayer:
			out.append(c)
		out.append_array(_canvas_layers(c))
	return out


func _on_size_changed() -> void:
	# Durante o slide o tween é dono das posições; ao terminar ele já
	# recalcula via _layout_instant().
	if _navigating:
		return
	_layout_instant()
