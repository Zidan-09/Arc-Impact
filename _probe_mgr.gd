extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var names: Array[String] = []
	for c in root.get_children():
		names.append(String(c.name))
	print("PROBE root children: ", names)
	print("PROBE current before: ", BackgroundMusicManager.current)
	print("PROBE loop before: ", BackgroundMusicManager.MUSIC_STREAM.loop)
	var m = BackgroundMusicManager.new()
	root.add_child(m)
	print("PROBE after add: current=", BackgroundMusicManager.current)
	print("PROBE current == m: ", BackgroundMusicManager.current == m)
	print("PROBE loop after: ", BackgroundMusicManager.MUSIC_STREAM.loop)
	print("PROBE m._player: ", m._player)
	if m._player != null:
		print("PROBE player playing=", m._player.playing, " stream.loop=", m._player.stream.loop, " same stream=", m._player.stream == BackgroundMusicManager.MUSIC_STREAM)
	print("PROBE m.get_script() == load(path): ", m.get_script() == load("res://components/background-music/background_music_manager.gd"))
	var names2: Array[String] = []
	for c in root.get_children():
		names2.append(String(c.name))
	print("PROBE root children after: ", names2)
	quit()
