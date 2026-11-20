extends TextureButton

## Botão "Fases" da home: SAI DO MAIN (destrutivo, fora do sistema
## deslizante). A cena atual é liberada e a tela Levels monta do zero,
## como antes. Sem args: Levels sempre volta para o Main.

const LEVELS_SCENE := "res://screens/levels.tscn"


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	InterfaceSoundManager.pluck()
	disabled = true
	get_tree().change_scene_to_file(LEVELS_SCENE)
