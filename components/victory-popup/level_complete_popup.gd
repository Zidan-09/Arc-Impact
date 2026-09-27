extends Control

signal home_pressed
signal retry_pressed
signal next_pressed

@onready var score_label: Label = $Panel/Margin/VBox/LevelInfo/ScoreContainer/Score
@onready var ammo_label: Label = $Panel/Margin/VBox/LevelInfo/AmmoContainer/Ammo
@onready var home_button: TextureButton = $Panel/Margin/VBox/ButtonsContainer/Home
@onready var retry_button: TextureButton = $Panel/Margin/VBox/ButtonsContainer/Retry
@onready var next_button: TextureButton = $Panel/Margin/VBox/ButtonsContainer/Next


func _ready() -> void:
	home_button.pressed.connect(_on_home_button_pressed)
	retry_button.pressed.connect(_on_retry_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)


func setup(score: int, ammo: int, has_next_level: bool = true) -> void:
	score_label.text = str(score)
	ammo_label.text = str(ammo)
	next_button.visible = has_next_level


func show_popup(score: int, ammo: int, has_next_level: bool = true) -> void:
	setup(score, ammo, has_next_level)
	visible = true


func _on_home_button_pressed() -> void:
	home_pressed.emit()


func _on_retry_button_pressed() -> void:
	retry_pressed.emit()


func _on_next_button_pressed() -> void:
	next_pressed.emit()
