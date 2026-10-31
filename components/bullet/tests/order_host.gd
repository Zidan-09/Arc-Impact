extends Node

var n = 0
var body = null


func _ready():
	body = get_node("Body")


func _physics_process(_delta):
	print("tick %d: y=%.4f v=%.4f" % [n, body.global_position.y, body.linear_velocity.y])
	n = n + 1
	if n >= 6:
		get_tree().quit(0)
