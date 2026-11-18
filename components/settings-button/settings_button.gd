extends TextureButton

## Botão "Settings" da home: abre a tela de configurações.
## Não toca em saves nem em áudio — apenas troca de cena; quem lê e
## aplica as preferências é a própria tela de configurações (via
## SettingsManager) e os gerenciadores no boot.

const SETTINGS_SCENE := "res://screens/settings.tscn"


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	InterfaceSoundManager.pluck()
	get_tree().change_scene_to_file(SETTINGS_SCENE)
