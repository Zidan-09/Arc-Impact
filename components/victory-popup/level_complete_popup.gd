extends Control

signal home_pressed
signal retry_pressed
signal next_pressed

@onready var score_label: Label = $Panel/VBoxContainer/LevelInfo/ScoreContainer/Score
@onready var ammo_label: Label = $Panel/VBoxContainer/LevelInfo/AmmoContainer/Ammo
@onready var next_button: TextureButton = $Panel/VBoxContainer/ButtonsContainer/Next


func setup(score: int, ammo: int, has_next_level: bool = true) -> void:
	score_label.text = str(score)
	ammo_label.text = str(ammo)

	next_button.visible = has_next_level


func _on_home_button_pressed() -> void:
	home_pressed.emit()


func _on_retry_button_pressed() -> void:
	retry_pressed.emit()


func _on_next_button_pressed() -> void:
	next_pressed.emit()
