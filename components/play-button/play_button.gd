extends TextureButton

const GAME_SCENE := "res://screens/game.tscn"
const HOME_SCENE := "res://screens/home.tscn"
## Script da tela de jogo: guarda o estado de sessão (fase selecionada
## e tela de retorno) em estáticos compartilhados entre cenas.
const GAME_SCRIPT := preload("res://screens/game.gd")

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	# Partida normal pela home: nenhuma fase específica selecionada e o
	# popup "Home" do jogo volta para a home (não para a tela Levels).
	GAME_SCRIPT.requested_level = 0
	GAME_SCRIPT.return_scene = HOME_SCENE
	get_tree().change_scene_to_file(GAME_SCENE)
