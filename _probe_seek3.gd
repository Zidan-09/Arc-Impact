extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var ogg = load("res://assets/obstacles/glass/breakingGlass_000.ogg")
	var s = ogg.instantiate_playback()
	print("PROBE instantiated: ", s != null)
	s.seek(3.55)
	print("PROBE ogg seek(3.55) before start -> pos=", s.get_playback_position())
	s.start()
	print("PROBE after start() -> pos=", s.get_playback_position())
	s.seek(3.55)
	print("PROBE seek after start -> pos=", s.get_playback_position())
	quit()
