class_name VolumeSlider
extends Control
## Slider de volume horizontal (0..100), no padrão do *settings screen*:
## trilha escura com borda roxa, preenchimento gradiente roxo→ciano
## limitado pela posição do knob e alçamento ciano. O valor é sempre
## derivado da POSIÇÃO ABSOLUTA do cursor sobre a trilha (mapeamento
## linear 0..track.size.x → 0..100, com clamp), de modo que o centro do
## knob acompanha o mouse 1:1 em qualquer resolução/escala de interface.
## Clique na trilha leva o valor direto para a posição clicada. O
## gerenciador de configurações é quem persiste; este nó só representa
## a seleção.

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

var dragging := false

## Valor atual em porcentagem (0..100). Fonte da verdade do slider.
var volume: int = 50

## Deslocamento (em pixels locais da trilha) entre o centro do knob e o
## cursor no momento em que o arraste começou pelo handle. Preserva a
## "pegada" para o knob não pular para o cursor no primeiro movimento;
## o movimento continua 1:1 (sem sensibilidade / sem acumulador).
var _drag_offset := 0.0

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
## o arraste (arrastar em seguida continua a ajustar). A pegada é zerada
## aqui porque o centro do knob vai exatamente para o cursor.
func _on_track_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_drag_offset = 0.0
			_seek_to(event.position.x)
			set_dragging(true)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_drag_offset = 0.0
			_seek_to(event.position.x)
			set_dragging(true)
			get_viewport().set_input_as_handled()


## Pressão no knob (handle): alterna o estado visual e memoriza a pegada
## (distância entre o centro do knob e o cursor) para o knob não pular
## para o cursor no primeiro movimento. O `event.position` chega nas
## coordenadas locais do receptor (Normal/Pressed preenchem o Handle por
## inteiro, logo equivalem às coordenadas do Handle).
func _on_slider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_grab_at(event.position.x)
			set_dragging(event.pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_grab_at(event.position.x)
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
		var local_motion := track.make_input_local(event) as InputEventMouseMotion
		_seek_to(local_motion.position.x + _drag_offset)
	elif event is InputEventScreenDrag:
		if event.index == 0:
			var local_drag := track.make_input_local(event) as InputEventScreenDrag
			_seek_to(local_drag.position.x + _drag_offset)


## Memoriza a pegada no knob: distância entre o centro do handle e o
## ponto pressionado, em pixels locais da trilha.
func _grab_at(handle_local_x: float) -> void:
	var pressed_track_x := _handle_local_to_track_x(handle_local_x)
	_drag_offset = _knob_center_track_x() - pressed_track_x


## Converte um X local do Handle (0..handle.size.x) para o X local da
## trilha, compensando o deslocamento entre os dois controles.
func _handle_local_to_track_x(handle_local_x: float) -> float:
	return handle.position.x + handle_local_x - track.position.x


## Centro atual do knob em pixels locais da trilha (0..track.size.x).
func _knob_center_track_x() -> float:
	return handle.position.x + handle.size.x * 0.5 - track.position.x


## Seleciona o valor por comando direto (fora da faixa é clampado).
func set_volume(value: int) -> void:
	_select_volume(clampi(value, MIN_VOLUME, MAX_VOLUME))


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
