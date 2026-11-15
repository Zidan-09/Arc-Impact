extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	await process_frame
	var via_const = BackgroundMusicManager.MUSIC_STREAM.loop
	var local = BackgroundMusicManager.MUSIC_STREAM
	var via_local = local.loop
	var via_cast = (BackgroundMusicManager.MUSIC_STREAM as AudioStreamMP3).loop
	var fresh = (load("res://assets/audio/Glass_Horizon.mp3") as AudioStreamMP3).loop
	print("PROBE via_const=", via_const, " via_local=", via_local, " via_cast=", via_cast, " fresh_load=", fresh)
	print("PROBE local==const: ", local == BackgroundMusicManager.MUSIC_STREAM, " local id=", local.get_instance_id(), " const id=", BackgroundMusicManager.MUSIC_STREAM.get_instance_id())
	quit()
