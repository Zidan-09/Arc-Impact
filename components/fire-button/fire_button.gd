extends Button

@onready var activeTexture = $active
@onready var inactiveTexture = $inactive

func _ready() -> void:
	activeTexture.visible = false
	inactiveTexture.visible = true
	
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	activeTexture.visible = true
	inactiveTexture.visible = false
