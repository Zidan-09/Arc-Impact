extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var ogg = load("res://assets/obstacles/glass/breakingGlass_000.ogg")
	var q := AudioStreamPlayer.new()
	q.stream = ogg
	root.add_child(q)
	q.play(3.55)
	for i in 12:
		await process_frame
		if i % 3 == 0:
			print("OGG frame ", i + 1, ": pos=", q.get_playback_position(), " playing=", q.playing)
	quit()
