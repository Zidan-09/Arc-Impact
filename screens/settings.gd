extends Control
## Tela de configurações: volumes (música/SFX), inversão do eixo Y e
## reset de progresso com confirmação. Todas as preferências são lidas
## e gravadas via SettingsManager (persistência automática, sem botão
## de salvar); o reset chama SaveManager e preserva as configurações
## porque os dois usam arquivos separados.

const INVERT_ON_TEXTURE := preload("res://assets/sprite/buttons/pause/active_pause.png")
const INVERT_OFF_TEXTURE := preload("res://assets/sprite/buttons/pause/inactive_pause.png")

@onready var music_slider: VolumeSlider = $Panel/Margin/VBox/AudioSection/MusicRow/MusicSlider
@onready var music_value: Label = $Panel/Margin/VBox/AudioSection/MusicRow/MusicValue
@onready var sfx_slider: VolumeSlider = $Panel/Margin/VBox/AudioSection/SFXRow/SFXSlider
@onready var sfx_value: Label = $Panel/Margin/VBox/AudioSection/SFXRow/SFXValue
@onready var invert_toggle: TextureButton = $Panel/Margin/VBox/ControlsSection/InvertRow/InvertToggle
@onready var invert_label: Label = $Panel/Margin/VBox/ControlsSection/InvertRow/InvertLabel
@onready var reset_button: Button = $Panel/Margin/VBox/ProgressSection/ResetRow/ResetButton
@onready var back_button: TextureButton = $Panel/Margin/VBox/BackButton

@onready var confirm_panel: Control = $ConfirmPanel
@onready var confirm_yes: Button = $ConfirmPanel/ConfirmBox/ConfirmMargin/ConfirmVBox/ConfirmButtons/ConfirmYes
@onready var confirm_no: Button = $ConfirmPanel/ConfirmBox/ConfirmMargin/ConfirmVBox/ConfirmButtons/ConfirmNo


func _ready() -> void:
	music_slider.volume_changed.connect(_on_music_changed)
	sfx_slider.volume_changed.connect(_on_sfx_changed)
	invert_toggle.pressed.connect(_on_invert_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)
	confirm_yes.pressed.connect(_on_reset_confirmed)
	confirm_no.pressed.connect(_on_cancel_reset)
	confirm_panel.visible = false

	music_slider.set_volume(SettingsManager.get_music_volume())
	music_value.text = str(SettingsManager.get_music_volume()) + "%"

	sfx_slider.set_volume(SettingsManager.get_sfx_volume())
	sfx_value.text = str(SettingsManager.get_sfx_volume()) + "%"

	_update_invert_visual(SettingsManager.is_invert_y())


func _on_music_changed(value: int) -> void:
	SettingsManager.set_music_volume(value)
	music_value.text = str(value) + "%"


func _on_sfx_changed(value: int) -> void:
	SettingsManager.set_sfx_volume(value)
	sfx_value.text = str(value) + "%"


func _on_invert_pressed() -> void:
	InterfaceSoundManager.pluck()
	var enabled := not SettingsManager.is_invert_y()
	SettingsManager.set_invert_y(enabled)
	_update_invert_visual(enabled)


func _update_invert_visual(enabled: bool) -> void:
	if enabled:
		invert_toggle.texture_normal = INVERT_ON_TEXTURE
		invert_toggle.texture_pressed = INVERT_OFF_TEXTURE
		invert_label.text = "Inversão do eixo Y: On"
	else:
		invert_toggle.texture_normal = INVERT_OFF_TEXTURE
		invert_toggle.texture_pressed = INVERT_ON_TEXTURE
		invert_label.text = "Inversão do eixo Y: Off"


func _on_reset_pressed() -> void:
	InterfaceSoundManager.pluck()
	confirm_panel.visible = true
	confirm_yes.grab_focus()


func _on_cancel_reset() -> void:
	InterfaceSoundManager.pluck()
	confirm_panel.visible = false
	reset_button.grab_focus()


func _on_reset_confirmed() -> void:
	InterfaceSoundManager.pluck()
	SaveManager.reset_progress()
	# Configurações intactas (user://settings.json separado do save).
	get_tree().change_scene_to_file("res://screens/home.tscn")


func _on_back_pressed() -> void:
	InterfaceSoundManager.pluck()
	get_tree().change_scene_to_file("res://screens/home.tscn")
