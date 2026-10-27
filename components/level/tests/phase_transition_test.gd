extends SceneTree
## Teste de ciclo de vida da transição de fase: bullets, rastros e shards
## da fase anterior NÃO sobrevivem a load_level (fix do vazamento de
## elementos transitórios entre fases). Roda headless, sem framework:
##   godot --headless --path . -s res://components/level/tests/phase_transition_test.gd
## Saída: "PHASE_TRANSITION_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).
## Pré-requisito: abrir o projeto no editor ao menos uma vez para o
## cache de global classes (class_name) estar atualizado.

const GAME_SCENE := preload("res://screens/game.tscn")
const SHARD_SCENE := preload("res://components/obstacles/glass/glass_shard_1.tscn")

## Espelha game.gd.TRANSIENT_GROUPS: os grupos que a transição limpa.
const TRANSIENT_GROUPS: Array[String] = ["bullets", "bullet_trails", "shards"]
const MAX_WAIT_FRAMES := 240


func _init() -> void:
	_run()


func _run() -> void:
	# O loop só começa a rodar depois do _init; process_frame garante que
	# root esteja pronto antes de instanciar a cena de jogo.
	await process_frame
	var failures := 0
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	failures += await _check_transition(game)
	if failures == 0:
		print("PHASE_TRANSITION_TEST: PASS")
	else:
		printerr("PHASE_TRANSITION_TEST: FAIL (%d checagens falharam)" % failures)
	quit(failures)


func _check_transition(game) -> int:
	var failures := 0
	# 1) A fase inicial termina de carregar (build é assíncrono no _ready).
	var frames := 0
	while bool(game._loading) and frames < MAX_WAIT_FRAMES:
		await process_frame
		frames += 1
	if bool(game._loading):
		printerr("  [setup] fase inicial não terminou de carregar.")
		return 1
	var level_node: Node2D = game.get_node("WorldArea/World/Level")
	if level_node.get_child_count() == 0:
		printerr("  [setup] fase inicial veio vazia.")
		failures += 1

	# 2) Cria os transitórios como o jogo faz: bala pela via real
	#    (game.shoot -> cannon.shoot, grupo "bullets" + rastro) e shard
	#    que entra no grupo "shards" pelo próprio _ready (mecanismo
	#    corrigido em shard.gd). Tudo no mesmo frame da transição, antes
	#    de qualquer física: determinístico.
	game.call("shoot")
	var frames_2 := 0
	while get_nodes_in_group("bullets").is_empty() and frames_2 < MAX_WAIT_FRAMES:
		await process_frame
		frames_2 += 1
	var bullets_antes := get_nodes_in_group("bullets")
	var bullet = bullets_antes[0] if not bullets_antes.is_empty() else null
	var shard := SHARD_SCENE.instantiate()
	level_node.add_child(shard)
	if get_nodes_in_group("bullets").is_empty() or not shard.is_in_group("shards"):
		printerr("  [setup] grupos transitórios não preenchidos (bullet/shard).")
		failures += 1
	if get_nodes_in_group("bullet_trails").is_empty():
		printerr("  [setup] bala não criou rastro (bullet_trails vazio).")
		failures += 1

	# 3) Transição de fase pelo mesmo caminho do popup "Next".
	var next_seed: int = int(game.current_seed) + 1
	var next_level: int = int(game.level_number) + 1
	await game.load_level(next_seed, next_level)
	await process_frame
	await process_frame

	# 4) Nada da fase anterior sobreviveu (árvore, física, grupos).
	for group in TRANSIENT_GROUPS:
		var left := get_nodes_in_group(group).size()
		if left != 0:
			printerr("  [transition] grupo '%s' com %d nó(s) após a troca de fase." % [group, left])
			failures += 1
	if is_instance_valid(bullet) or is_instance_valid(shard):
		printerr("  [transition] bullet/shard da fase anterior ainda existem (física ativa).")
		failures += 1
	for child in level_node.get_children():
		if not child.is_in_group("level_spawned"):
			printerr("  [transition] órfão em Level após a troca: %s." % String(child.name))
			failures += 1

	# 5) A nova fase começou normalmente, com os próprios elementos.
	if int(game.level_number) != next_level or bool(game.game_over):
		printerr("  [transition] nova fase não iniciou (level=%d, game_over=%s)." % [
			int(game.level_number), str(bool(game.game_over))
		])
		failures += 1
	if level_node.get_child_count() == 0:
		printerr("  [transition] nova fase sem elementos.")
		failures += 1
	return failures
