extends Control

@onready var level_label: Label = $Info/Column/Level
@onready var ammo_label: Label = $Info/Column/Ammo


func set_ammo(total: int, left: int) -> void:
	ammo_label.text = "Munição: %d" % left


func set_level(level_number: int) -> void:
	level_label.text = "Fase: %d" % level_number
