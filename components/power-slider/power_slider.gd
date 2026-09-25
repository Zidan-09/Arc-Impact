extends Control

@onready var handle: Control = $Handle
@onready var normal: TextureRect = $Handle/Normal
@onready var pressed: TextureRect = $Handle/Pressed
@onready var power_gradient: ColorRect = $PowerGradient

@export var min_power: float = 0.3
@export var max_power: float = 1.0

@onready var track: TextureRect = $Track

@export_range(0.0001, 0.01, 0.0001)
var sensitivity: float = 0.0012

var dragging := false
var power: float = 0.3

signal power_changed(value: float)

func _ready() -> void:
	# O drag só pode começar sobre o visual do Track ou do Handle
	# (Normal/Pressed). A raiz continua IGNORE, então cliques fora caem
	# no _unhandled_input do Controller (ângulo do Cannon).
	track.gui_input.connect(_on_slider_gui_input)
	handle.gui_input.connect(_on_slider_gui_input)
	normal.gui_input.connect(_on_slider_gui_input)
	pressed.gui_input.connect(_on_slider_gui_input)
	update_visual()
	update_handle_position()


func set_dragging(value: bool) -> void:
	if dragging == value:
		return
	dragging = value
	update_visual()


func update_visual() -> void:
	normal.visible = not dragging
	pressed.visible = dragging


func _on_slider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			set_dragging(event.pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		set_dragging(event.pressed)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Aqui NÃO se inicia drag: press fora do Track/Handle nem chega aqui
	# como gui_input, então é ignorado. Só continua um drag já ativo
	# (motion) e encerra em qualquer soltura (mesmo fora do visual).
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
			set_dragging(false)
	elif event is InputEventScreenTouch:
		if not event.pressed and dragging:
			set_dragging(false)

	if not dragging:
		return

	if event is InputEventMouseMotion:
		update_power(-event.relative.y)
	elif event is InputEventScreenDrag:
		if event.index == 0:
			update_power(-event.relative.y)


func update_power(delta: float) -> void:
	power += delta * sensitivity
	power = clampf(power, min_power, max_power)

	update_handle_position()
	power_changed.emit(power)


func update_handle_position() -> void:
	var t := inverse_lerp(min_power, max_power, power)

	var limits := get_handle_limits()

	handle.position.y = lerpf(
		limits.y,
		limits.x,
		t
	)
	
	power_gradient.position.y = handle.position.y + 50
	power_gradient.size.y = limits.y - handle.position.y + 50

func get_handle_limits() -> Vector2:
	var half_handle_height := handle.size.y / 2.0

	var top := track.position.y + half_handle_height
	var bottom := track.position.y + track.size.y - half_handle_height - 120

	return Vector2(top, bottom)
