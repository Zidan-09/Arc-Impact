extends Control

## Slider de força em 10 níveis discretos. A seleção é sempre um inteiro
## de 1 a POWER_LEVELS: o arraste acumula em um valor contínuo
## (`_raw_power`, suave para mouse e touch) e o snap para o nível mais
## próximo acontece a cada movimento. A conversão nível -> força mora
## só em `level_to_power()` — `power` e o sinal `power_changed` seguem
## entregando a força efetiva, então o sistema de disparo
## (game.gd / cannon_controller.gd / Cannon) não muda.

## Número exato de níveis do slider (sempre 1..POWER_LEVELS).
const POWER_LEVELS := 10

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

## Nível selecionado — fonte da verdade do slider (inteiro, 1..POWER_LEVELS).
var power_level: int = 1

## Força efetiva do nível selecionado. Derivada (nunca armazenada), de
## modo que um valor intermediário é impossível por construção.
var power: float:
	get:
		return level_to_power(power_level)

## Acumulador contínuo do arraste: mantém o movimento suave (o delta do
## mouse/touch não é quantizado) e é convertido no nível mais próximo a
## cada movimento. É sincronizado só por `set_level` (comando direto) —
## NUNCA durante o arraste, senão eventos pequenos nunca cruzariam o
## meio do passo e o slider travaria no nível atual.
var _raw_power: float = 0.3

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
	# Garante o invariante inicial (nível -> força) com os exports atuais.
	set_level(power_level)


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


## Conversão NÍVEL (1..10) -> força efetiva do disparo. ÚNICO ponto do
## projeto que faz esse mapeamento: linear entre `min_power` (nível 1) e
## `max_power` (nível 10), com os níveis intermediários proporcionais.
## Quem precisa de força continua lendo `power`/`power_changed`.
func level_to_power(level: int) -> float:
	var t := float(clampi(level, 1, POWER_LEVELS) - 1) / float(POWER_LEVELS - 1)
	return lerpf(min_power, max_power, t)


## Conversão inversa (força -> nível mais próximo) — o snap do arraste.
## Só retorna valores de 1 a POWER_LEVELS.
func power_to_level(value: float) -> int:
	var t := clampf(inverse_lerp(min_power, max_power, value), 0.0, 1.0)
	return int(round(t * float(POWER_LEVELS - 1))) + 1


func update_power(delta: float) -> void:
	# Arraste contínuo (delta acumulado sem quantizar) + snap a cada
	# movimento: o indicador encaixa na posição discreta mais próxima e
	# a seleção final é sempre um dos 10 níveis. O acumulador segue
	# contínuo aqui — é ele que permite arrastes em muitos eventos
	# pequenos atravessarem o meio do passo.
	_raw_power = clampf(_raw_power + delta * sensitivity, min_power, max_power)
	_select_level(power_to_level(_raw_power))


## Seleciona o nível por comando direto (fora da faixa é clampado para
## 1..POWER_LEVELS) e move o acumulador do arraste para o nível escolhido,
## de modo que o próximo arraste parte dele.
func set_level(level: int) -> void:
	var new_level := clampi(level, 1, POWER_LEVELS)
	_raw_power = level_to_power(new_level)
	_select_level(new_level)


## Aplica o nível selecionado (fonte da verdade), reposiciona o indicador
## na posição discreta e emite `power_changed` com a força do nível.
func _select_level(level: int) -> void:
	power_level = clampi(level, 1, POWER_LEVELS)
	update_handle_position()
	power_changed.emit(power)


func update_handle_position() -> void:
	# Posição puramente discreta: 10 pontos fixos entre os limites do track.
	var t := float(power_level - 1) / float(POWER_LEVELS - 1)

	var limits := get_handle_limits()

	handle.position.y = lerpf(
		limits.y,
		limits.x,
		t
	)
	
	power_gradient.position.y = handle.position.y
	power_gradient.size.y = limits.y - handle.position.y + 100

func get_handle_limits() -> Vector2:
	var half_handle_height := handle.size.y / 2.0

	var top := track.position.y + half_handle_height + 50
	var bottom := track.position.y + track.size.y - half_handle_height - 120

	return Vector2(top, bottom)
