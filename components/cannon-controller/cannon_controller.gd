extends Node2D
## Hospeda a fase jogável (Etapa 7, docs/plan.md §12): carrega a fase
## gerada no contêiner Level, posiciona o canhão, controla munição e
## declara vitória/derrota. Mira, força e FireButton inalterados.
## Desvios conscientes do plano: status mínimo via StatusLabel (o
## hud.tscn do fluxo game.tscn, com slider+botão próprios, será unificado
## num passo futuro); screens/game.tscn intacto pelo mesmo motivo.

const DEFAULT_SEED := 1
const DEFAULT_LEVEL := 1
const END_DELAY := 8.0 # s após esgotar a munição sem vitória => derrota

@onready var cannon = $Cannon
@onready var power_slider = $PowerSlider
@onready var fire_button: TextureButton = $FireButton
@onready var level_node: Node2D = $Level
@onready var status_label: Label = $StatusLabel

var builder: LevelBuilder

var current_def: LevelDefinition = null
var current_target: Target = null
var level_number := DEFAULT_LEVEL
var ammo_total := 0
var ammo_left := 0
var game_over := true
var won := false

var _loading := false
var _awaiting_end := false
var _end_timer := 0.0
var _dragging_angle := false


func _ready() -> void:
	fire_button.focus_mode = Control.FOCUS_NONE
	fire_button.pressed.connect(shoot)
	cannon.bullet_container = level_node
	builder = LevelBuilder.new()
	add_child(builder)
	load_level(DEFAULT_SEED, DEFAULT_LEVEL)


## Gera (async, sem travar o jogo) e monta a fase. Chamável de novo
## para trocar de fase/seed — ex.: `load_level(42, 3)`.
func load_level(seed_value: int, new_level_number: int) -> void:
	if _loading:
		return
	_loading = true
	game_over = true
	won = false
	_awaiting_end = false
	_end_timer = 0.0
	ammo_total = 0
	ammo_left = 0
	current_def = null
	current_target = null
	level_number = new_level_number
	_status("Gerando fase %d..." % level_number)
	var result := await ProceduralLevelGenerator.generate(seed_value, level_number, self)
	var def: LevelDefinition = result["def"]
	if bool(result["fallback_used"]):
		push_warning("CannonController: fallback usado (%s)." % str(result["log"]))
	var built := await builder.build(level_node, def)
	current_def = def
	cannon.position = def.cannon_position
	ammo_total = def.ammo
	ammo_left = def.ammo
	current_target = built["target"] as Target
	if current_target != null:
		current_target.hit.connect(_on_target_hit)
	game_over = false
	_loading = false
	_status("Fase %d — %d tiros" % [level_number, ammo_left])


func shoot() -> void:
	if game_over or _loading:
		return
	if ammo_left <= 0:
		return
	ammo_left -= 1
	cannon.shoot(power_slider.power)
	_end_timer = 0.0
	_awaiting_end = ammo_left <= 0
	_status("Fase %d — %d tiros" % [level_number, ammo_left])


func _physics_process(delta: float) -> void:
	if not _awaiting_end or won or game_over:
		return
	_end_timer += delta
	var bullets := get_tree().get_nodes_in_group("bullets")
	if bullets.is_empty() or _end_timer >= END_DELAY:
		_defeat()


func _on_target_hit(_body: Bullet) -> void:
	if game_over or won:
		return
	won = true
	game_over = true
	_awaiting_end = false
	_status("Vitória! Fase %d com %d tiro(s) sobrando" % [level_number, ammo_left])


func _defeat() -> void:
	game_over = true
	_awaiting_end = false
	_status("Derrota — sem munição. Fase %d" % level_number)


func _status(text: String) -> void:
	status_label.text = text


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging_angle = false
	elif event is InputEventScreenTouch:
		if event.index == 0 and not event.pressed:
			_dragging_angle = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_angle = event.pressed
	elif event is InputEventMouseMotion and _dragging_angle:
		cannon.rotate_cannon(-event.relative.y)
	elif event is InputEventScreenTouch:
		if event.index == 0:
			_dragging_angle = event.pressed
	elif event is InputEventScreenDrag:
		if event.index == 0 and _dragging_angle:
			cannon.rotate_cannon(-event.relative.y)
