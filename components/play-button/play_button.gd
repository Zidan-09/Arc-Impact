extends TextureButton

## Botão "Jogar" da home: slide para o Game (sistema deslizante).
## Nenhuma fase específica selecionada (0 = progresso salvo); se o Game
## já estiver carregado, o slide preserva a fase em memória.
## Fora do Main (standalone): fallback destrutivo clássico.

const GAME_SCENE := "res://screens/game.tscn"


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	InterfaceSoundManager.pluck()
	var nav = _navigator()
	if nav != null:
		if nav.is_navigating():
			return
		nav.navigate_to("game")
		return
	# Fallback standalone (fora do Main): destrutivo clássico.
	get_tree().change_scene_to_file(GAME_SCENE)


## Navigator acima de nós na árvore (duck-typing: qualquer nó com
## `navigate_to`/`is_navigating`). Null no modo standalone/testes.
func _navigator():
	var n := get_parent()
	while n != null:
		if n.has_method("navigate_to") and n.has_method("is_navigating"):
			return n
		n = n.get_parent()
	return null
