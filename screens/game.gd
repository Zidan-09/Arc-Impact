extends Control

@onready var world: Node2D = $WorldArea/World
@onready var level_node: Node2D = $WorldArea/World/Level
@onready var cannon: Cannon = $WorldArea/World/Cannon
@onready var hud: Control = $Hud

var builder: LevelBuilder
var current_def: LevelDefinition = null
var level_number := 1


func _ready() -> void:
	builder = LevelBuilder.new()
	add_child(builder)
	cannon.bullet_container = level_node
	load_fixed_level()


func load_fixed_level() -> void:
	var cfg := DifficultyTable.get_config(1)
	var def := ProceduralLevelGenerator.ultimate_fallback(1, 1, cfg)
	await builder.build(level_node, def)
	current_def = def
	cannon.position = def.cannon_position
	hud.set_level(level_number)
	hud.set_ammo(def.ammo, def.ammo)
