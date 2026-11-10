extends Control
## Tela Levels: mapa horizontal de progressão com seleção de fase.
##
## Lê o progresso salvo apenas para exibir e posicionar o mapa — nunca
## escreve nele. A fase escolhida é repassada ao jogo pelo estado de
## sessão em `screens/game.gd` (`requested_level` / `return_scene`), e o
## popup "Home" do jogo retorna para cá, preservando a navegação.

const LevelMap := preload("res://components/level-map/level_map.gd")
const GAME_SCRIPT := preload("res://screens/game.gd")

const GAME_SCENE := "res://screens/game.tscn"
const HOME_SCENE := "res://screens/home.tscn"
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


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(HOME_SCENE)


## Fase desbloqueada escolhida: inicia exatamente ela no jogo, usando o
## gerador procedural existente. Nada é gravado aqui — jogar uma fase
## antiga não move o progresso máximo.
func _on_level_selected(level: int) -> void:
	GAME_SCRIPT.requested_level = level
	GAME_SCRIPT.return_scene = LEVELS_SCENE
	get_tree().change_scene_to_file(GAME_SCENE)


## Fase bloqueada: feedback visual, sem iniciar a fase.
func _on_blocked_selected(level: int) -> void:
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
