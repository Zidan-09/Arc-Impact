extends Control

signal pause_pressed

@onready var level_label: Label = $Info/Column/Level
@onready var ammo_label: Label = $Info/Column/Ammo
@onready var pause_button: TextureButton = $Pause


func _ready() -> void:
	pause_button.pressed.connect(_on_pause_button_pressed)


func _on_pause_button_pressed() -> void:
	pause_pressed.emit()


func set_ammo(total: int, left: int) -> void:
	ammo_label.text = "Munição: %d" % left


func set_level(level_number: int) -> void:
	level_label.text = "Fase: %d" % level_number
