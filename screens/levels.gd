extends Control
## Tela Levels: mapa horizontal de progressão com seleção de fase.
## FORA do sistema deslizante (troca destrutiva, como antes): quem chega
## aqui veio do Main e o Main foi liberado; voltar/selecionar reconstrói
## o Main do zero através de `ScreenNavigator.start_*`.
##
## Lê o progresso salvo apenas para exibir e posicionar o mapa — nunca
## escreve nele. Nada é gravado aqui — jogar uma fase antiga não move o
## progresso máximo.

const LevelMap := preload("res://components/level-map/level_map.gd")

## Reconstrução do Main (único destino destrutivo desta tela).
const MAIN_SCENE := "res://screens/main.tscn"
const LEVELS_SCENE := "res://screens/levels.tscn"
## Duração do aviso de fase bloqueada (s) e início do fade.
const HINT_DURATION := 1.6
const HINT_FADE := 0.4

@onready var map: LevelMap = $MapArea/LevelMap
@onready var subtitle: Label = $Header/Subtitle
@onready var back_button: TextureButton = $Header/Back/Home
@onready var hint: Label = $Hint

var _hint_timer := 0.0


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	map.level_selected.connect(_on_level_selected)
	map.blocked_selected.connect(_on_blocked_selected)
	var progress: Dictionary = SaveManager.load_progress()
	subtitle.text = "Progresso: fase %d" % int(progress["level"])
	await _wait_for_layout()
	await map.setup(int(progress["level"]))


## Espera o primeiro layout da tela antes de medir/rolar o mapa.
func _wait_for_layout() -> void:
	for _i in range(8):
		if map.size.x > 0.0 and map.size.y > 0.0:
			return
		await get_tree().process_frame


## Voltar: reconstrói o Main no Home (o Main anterior foi liberado).
func _on_back_pressed() -> void:
	InterfaceSoundManager.pluck()
	ScreenNavigator.start_target = "home"
	ScreenNavigator.start_level = 0
	get_tree().change_scene_to_file(MAIN_SCENE)


## Fase desbloqueada escolhida: reconstrói o Main já nascendo no Game
## com exatamente ela (seed pela regra +1 ancorada no save). Nada é
## gravado aqui — jogar uma fase antiga não move o progresso máximo.
func _on_level_selected(level: int) -> void:
	InterfaceSoundManager.select_sound()
	ScreenNavigator.start_target = "game"
	ScreenNavigator.start_level = level
	get_tree().change_scene_to_file(MAIN_SCENE)


## Fase bloqueada: feedback visual, sem sair da tela.
func _on_blocked_selected(level: int) -> void:
	InterfaceSoundManager.select_sound()
	_show_hint("Fase %d bloqueada" % level)


func _show_hint(text: String) -> void:
	hint.text = text
	hint.visible = true
	hint.modulate = Color.WHITE
	_hint_timer = HINT_DURATION


func _process(delta: float) -> void:
	if _hint_timer <= 0.0:
		return
	_hint_timer -= delta
	var fade := hint.modulate
	fade.a = clampf(_hint_timer / HINT_FADE, 0.0, 1.0)
	hint.modulate = fade
	if _hint_timer <= 0.0:
		hint.visible = false
