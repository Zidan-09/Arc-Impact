extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var mp3 = load("res://assets/audio/music/glass_horizon.mp3")
	var p := AudioStreamPlayer.new()
	p.stream = mp3
	root.add_child(p)
	p.play()
	for i in 6:
		await process_frame
		print("MP3 frame ", i + 1, ": pos=", p.get_playback_position(), " playing=", p.playing)
	var ogg = load("res://assets/audio/floor/footstep_concrete_000.ogg")
	var q := AudioStreamPlayer.new()
	q.stream = ogg
	root.add_child(q)
	q.play(0.5)
	await physics_frame
	await physics_frame
	print("OGG seek(0.5): pos=", q.get_playback_position(), " playing=", q.playing)
	print("loop antes=", (mp3 as AudioStreamMP3).loop)
	(mp3 as AudioStreamMP3).loop = true
	p.play(0.0)
	await process_frame
	print("loop depois=", (mp3 as AudioStreamMP3).loop, " pos=", p.get_playback_position())
	quit()
