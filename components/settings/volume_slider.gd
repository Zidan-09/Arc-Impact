class_name VolumeSlider
extends Control
## Slider de volume horizontal (0..100), no padrão do *settings screen*:
## trilha escura com borda roxa, preenchimento gradiente roxo→ciano
## limitado pela posição do knob e alçamento ciano. Arraste horizontal
## acumulado em `_raw_volume` (suave para mouse e touch), snap para o
## inteiro mais próximo a cada movimento e emissão de `volume_changed`
## com o valor em porcentagem. Clique na trilha leva o valor direto
## para a posição clicada. O gerenciador de configurações é quem
## persiste; este nó só representa a seleção.

const MIN_VOLUME := 0
const MAX_VOLUME := 100

@onready var handle: Control = $Handle
@onready var normal: TextureRect = $Handle/Normal
@onready var pressed: TextureRect = $Handle/Pressed
## O Track é um Panel (estilo dark com borda roxa) com um
## TextureRect "Fill" dentro, que recebe o gradiente
## roxo→ciano limitado pela posição do knob.
@onready var track: Panel = $Track
@onready var fill: TextureRect = $Track/Fill

@export_range(0.05, 2.0, 0.01)
var sensitivity: float = 0.4

var dragging := false

## Valor atual em porcentagem (0..100). Fonte da verdade do slider.
var volume: int = 50

## Acumulador contínuo do arraste: mantém o movimento suave e é
## convertido no inteiro mais próximo a cada movimento.
var _raw_volume: float = 50.0

signal volume_changed(value: int)


func _ready() -> void:
	track.gui_input.connect(_on_track_gui_input)
	handle.gui_input.connect(_on_slider_gui_input)
	normal.gui_input.connect(_on_slider_gui_input)
	pressed.gui_input.connect(_on_slider_gui_input)
	# O layout final do slider (e da trilha) só existe depois do sort
	# do container; recomputa a posição do alçamento quando chegar.
	resized.connect(update_handle_position)
	track.resized.connect(update_handle_position)
	update_visual()
	set_volume(volume)


func set_dragging(value: bool) -> void:
	if dragging == value:
		return
	dragging = value
	update_visual()


func update_visual() -> void:
	normal.visible = not dragging
	pressed.visible = dragging


## Clique/tap na trilha: leva o valor direto para a posição e inicia
## o arraste (arrastar em seguida continua a ajustar).
func _on_track_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_seek_to(event.position.x)
			set_dragging(true)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_seek_to(event.position.x)
			set_dragging(true)
			get_viewport().set_input_as_handled()


## Arraste pelo alçamento (handle): alterna o estado visual.
func _on_slider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			set_dragging(event.pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		set_dragging(event.pressed)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
			set_dragging(false)
	elif event is InputEventScreenTouch:
		if not event.pressed and dragging:
			set_dragging(false)

	if not dragging:
		return

	if event is InputEventMouseMotion:
		update_volume(event.relative.x)
	elif event is InputEventScreenDrag:
		if event.index == 0:
			update_volume(event.relative.x)


## Arraste horizontal: esquerda diminui, direita aumenta.
func update_volume(delta: float) -> void:
	_raw_volume = clampf(_raw_volume + delta * sensitivity, float(MIN_VOLUME), float(MAX_VOLUME))
	_select_volume(int(round(_raw_volume)))


## Seleciona o valor por comando direto (fora da faixa é clampado).
func set_volume(value: int) -> void:
	var clean := clampi(value, MIN_VOLUME, MAX_VOLUME)
	_raw_volume = float(clean)
	_select_volume(clean)


func _seek_to(local_x: float) -> void:
	# `event.position` chega relativo ao próprio Track (0..track.size.x).
	var width := maxf(track.size.x, 1.0)
	var t := clampf(local_x / width, 0.0, 1.0)
	set_volume(int(round(lerpf(float(MIN_VOLUME), float(MAX_VOLUME), t))))


func _select_volume(value: int) -> void:
	volume = clampi(value, MIN_VOLUME, MAX_VOLUME)
	update_handle_position()
	volume_changed.emit(volume)


func update_handle_position() -> void:
	var t := float(volume - MIN_VOLUME) / float(MAX_VOLUME - MIN_VOLUME)
	var limits := get_handle_limits()
	handle.position.x = lerpf(limits.x, limits.y, t)
	# O Fill acompanha o knob: vai da borda interna esquerda da trilha
	# até o centro do knob, sem passar por cima da borda direita.
	var half := handle.size.x * 0.5
	var knob_center := handle.position.x + half - track.position.x
	fill.offset_right = clampf(knob_center, fill.offset_left, track.size.x - fill.offset_left)


func get_handle_limits() -> Vector2:
	# Limites para a POSIÇÃO (canto superior esquerdo) do knob de modo
	# que o CENTRO dele percorra a trilha de ponta a ponta: em 0% o
	# preenchimento fica vazio e em 100% encosta na extremidade direita.
	var half := handle.size.x * 0.5
	var left := track.position.x - half
	var right := track.position.x + track.size.x - half
	return Vector2(left, right)
