extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var mp3 = load("res://assets/audio/Glass_Horizon.mp3")
	var p := AudioStreamPlayer.new()
	p.stream = mp3
	root.add_child(p)
	p.play(50.0)
	var ogg = load("res://assets/obstacles/glass/breakingGlass_000.ogg")
	var q := AudioStreamPlayer.new()
	q.stream = ogg
	root.add_child(q)
	q.play(3.55)
	for i in 15:
		await process_frame
	print("SEEK mp3(50.0) pos=", p.get_playback_position(), " | ogg(3.55) pos=", q.get_playback_position())
	quit()
