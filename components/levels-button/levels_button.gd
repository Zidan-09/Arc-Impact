extends Button

## Botão "Fases" da home: abre o mapa de progresso (tela Levels).
## Não toca no save — apenas troca de cena; quem lê o progresso é a
## própria tela Levels.

const LEVELS_SCENE := "res://screens/levels.tscn"


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	get_tree().change_scene_to_file(LEVELS_SCENE)
