extends SceneTree
func _initialize() -> void:
	print("BUSES: ", AudioServer.get_bus_count())
	for i in AudioServer.get_bus_count():
		print("BUS ", i, " name=", AudioServer.get_bus_name(i), " send=", AudioServer.get_bus_send(i), " vol=", AudioServer.get_bus_volume_db(i))
	quit()
