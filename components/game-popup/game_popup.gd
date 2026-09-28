extends Control

signal home_pressed
signal retry_pressed
signal next_pressed

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Panel/Margin/VBox/Subtitle
@onready var score_label: Label = $Panel/Margin/VBox/LevelInfo/ScoreContainer/Score
@onready var ammo_label: Label = $Panel/Margin/VBox/LevelInfo/AmmoContainer/Ammo
@onready var home_button: TextureButton = $Panel/Margin/VBox/ButtonsContainer/Home
@onready var retry_button: TextureButton = $Panel/Margin/VBox/ButtonsContainer/Retry
@onready var next_button: TextureButton = $Panel/Margin/VBox/ButtonsContainer/Next


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	home_button.pressed.connect(_on_home_button_pressed)
	retry_button.pressed.connect(_on_retry_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)


func setup(score: int, ammo: int, has_next_level: bool = true) -> void:
	score_label.text = str(score)
	ammo_label.text = str(ammo)
	next_button.visible = has_next_level


func show_popup(score: int, ammo: int, has_next_level: bool = true) -> void:
	title_label.text = "VITÓRIA"
	title_label.add_theme_color_override("font_color", Color(0.133, 0.827, 0.933))
	title_label.add_theme_color_override("font_shadow_color", Color(0.851, 0.275, 0.937, 0.9))
	subtitle_label.text = "Alvo atingido!"
	setup(score, ammo, has_next_level)
	visible = true


func show_defeat_popup(score: int, ammo: int) -> void:
	title_label.text = "DERROTA"
	title_label.add_theme_color_override("font_color", Color(1.0, 0.23, 0.42))
	title_label.add_theme_color_override("font_shadow_color", Color(1.0, 0.23, 0.42, 0.6))
	subtitle_label.text = "Tente novamente"
	setup(score, ammo, false)
	visible = true


func show_pause_popup(score: int, ammo: int) -> void:
	title_label.text = "PAUSE"
	title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	title_label.add_theme_color_override("font_shadow_color", Color(0.851, 0.275, 0.937, 0.9))
	subtitle_label.text = "Jogo pausado"
	setup(score, ammo, true)
	visible = true


func _on_home_button_pressed() -> void:
	home_pressed.emit()


func _on_retry_button_pressed() -> void:
	retry_pressed.emit()


func _on_next_button_pressed() -> void:
	next_pressed.emit()
