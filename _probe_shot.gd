extends SceneTree
## Probe temporário: captura da tela Levels com o mapa em estado
## avançado (fase 6 = atual, 1-5 concluídas) para validar o visual do
## caminho percorrido e dos nós DONE. Não escreve no SaveManager.

const OUT := "C:/Users/zidan/AppData/Local/Temp/opencode/levels_done_shot.png"


func _init() -> void:
	_run()


func _run() -> void:
	var levels: Node = load("res://screens/levels.tscn").instantiate()
	root.add_child(levels)
	for _i in range(20):
		await process_frame
	var map: Node = levels.get_node("MapArea/LevelMap")
	map.setup(6)
	for _i in range(45):
		await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("capture: imagem vazia")
		quit(1)
		return
	var err := img.save_png(OUT)
	print("capture err=%d size=%s" % [err, str(img.get_size())])
	quit(0 if err == OK else 1)
