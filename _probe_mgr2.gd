extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var a = root.get_node("BackgroundMusic")
	print("PROBE script == load: ", a.get_script() == load("res://components/background-music/background_music_manager.gd"))
	print("PROBE a._player: ", a._player)
	if a._player != null:
		var s = a._player.stream
		print("PROBE player.stream class: ", s.get_class(), " path: ", s.resource_path)
		print("PROBE player.stream id: ", s.get_instance_id())
		print("PROBE player.stream.loop: ", s.loop)
		print("PROBE class const id: ", BackgroundMusicManager.MUSIC_STREAM.get_instance_id())
		print("PROBE class const loop: ", BackgroundMusicManager.MUSIC_STREAM.loop)
		print("PROBE same object: ", s == BackgroundMusicManager.MUSIC_STREAM)
		print("PROBE playing: ", a._player.playing, " bus: ", a._player.bus, " vol: ", a._player.volume_db)
	quit()
