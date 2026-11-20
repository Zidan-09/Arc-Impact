extends TextureButton

## Botão "Settings" da home: slide para as configurações (sistema
## deslizante). Não toca em saves nem em áudio — apenas navega; quem
## lê e aplica as preferências é a própria tela de configurações (via
## SettingsManager) no `enter()`/refresh.
## Fora do Main (standalone): fallback destrutivo clássico.

const SETTINGS_SCENE := "res://screens/settings.tscn"


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	InterfaceSoundManager.pluck()
	var nav = _navigator()
	if nav != null:
		if nav.is_navigating():
			return
		nav.navigate_to("settings")
		return
	# Fallback standalone (fora do Main): destrutivo clássico.
	get_tree().change_scene_to_file(SETTINGS_SCENE)


## Navigator acima de nós na árvore (duck-typing). Null standalone.
func _navigator():
	var n := get_parent()
	while n != null:
		if n.has_method("navigate_to") and n.has_method("is_navigating"):
			return n
		n = n.get_parent()
	return null
