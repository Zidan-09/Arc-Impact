extends SceneTree
## Regressão da feature: Música de fundo contínua (Background Music).
##
## Cobre os critérios de aceitação:
##  - Autoload registrado no project.godot (o jogo real carrega no boot);
##  - stream único em loop, bus "Music" dedicado e volume de fundo,
##    com o bus Master (SFX) intacto;
##  - UMA única instância do reprodutor em toda a árvore;
##  - a música começa sozinha no boot e sobrevive às trocas de cena
##    (home → Levels → Game → home): a posição de reprodução nunca
##    recua (um reinício faria voltar a ~0);
##  - carregamento de fase, retry/next (load_level) e popups de
##    vitória/derrota/pause não reiniciam nem interrompem a trilha;
##  - SFX intactos na partida: ImpactSoundManager com pool completo,
##    vozes no bus Master, play()/stop_all() independentes da música;
##  - instância duplicada do gerenciador é descartada (sem 2º player);
##  - retorno ao menu não cria segunda instância.
##
## Vitória/derrota: os popups NÃO trocam de cena (permanecem em
## game.tscn), então a continuidade é intrínseca; os caminhos de
## transição pós-popup (next/retry → load_level, home → troca de cena)
## são cobertos abaixo junto com a exibição explícita dos popups.
##
## O Autoload também é instanciado pelo modo `-s` (validado pelo
## próprio teste), então aqui se audita a instância REAL do projeto —
## na posição de root que ocupa no jogo — e o mecanismo de troca de
## cena via change_scene_to_file, exatamente como o jogo real usa.
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/background-music/tests/background_music_test.gd
## Saída: "BACKGROUND_MUSIC_TEST: PASS" (exit 0) ou FAIL com detalhes (exit 1).

const HOME_SCENE := "res://screens/home.tscn"
const LEVELS_SCENE := "res://screens/levels.tscn"
const GAME_SCENE := "res://screens/game.tscn"

const MAX_WAIT_FRAMES := 240

## Posição mínima "aquecida" antes das checagens de continuidade: o
## driver de áudio dummy do headless avança em blocos (~90 ms), então a
## partir de >50 ms acumulados qualquer reinício fica evidente (volta a
## ~0, muito abaixo do máximo já atingido).
const WARM_POS := 0.05

var _failures := 0
var _manager: BackgroundMusicManager
var _last_pos := 0.0


func _init() -> void:
	_run()


func _run() -> void:
	# O loop só começa a rodar depois do _init; process_frame garante
	# que root esteja pronto antes de montar o cenário.
	await process_frame
	await _case_project_config()
	await _case_boot_singleton()
	await _case_home_menu()
	await _case_levels_screen()
	await _case_game_session()
	await _case_victory_defeat_popups()
	await _case_pause_popup()
	await _case_retry_next()
	await _case_back_to_menu()
	await _case_duplicate_instance()

	if _failures == 0:
		print("BACKGROUND_MUSIC_TEST: PASS")
	else:
		printerr("BACKGROUND_MUSIC_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


## A) Configuração do projeto: Autoload registrado, bus dedicado e
## asset carregado.
func _case_project_config() -> void:
	var cfg: String = str(ProjectSettings.get_setting("autoload/BackgroundMusic", ""))
	_check(cfg == "*res://components/background-music/background_music_manager.gd",
		"config: Autoload BackgroundMusic registrado ('%s')" % cfg)
	var music_bus := AudioServer.get_bus_index("Music")
	_check(music_bus > 0, "config: bus Music existe no layout (índice %d)" % music_bus)
	if music_bus > 0:
		_check(AudioServer.get_bus_send(music_bus) == "Master",
			"config: bus Music envia para Master")
	_check(AudioServer.get_bus_name(0) == "Master" and AudioServer.get_bus_send(0) == "",
		"config: bus Master (SFX) intacto")
	_check(BackgroundMusicManager.MUSIC_STREAM.get_length() > 60.0,
		"config: stream da música carregado (%.1f s)" %
			BackgroundMusicManager.MUSIC_STREAM.get_length())


## B) Boot: o Autoload nasce na raiz com UM único reprodutor e a
## trilha já tocando (no modo `-s` os autoloads também são criados —
## aqui se valida a instância REAL do projeto).
func _case_boot_singleton() -> void:
	var autoload := root.get_node_or_null("BackgroundMusic")
	_check(autoload is BackgroundMusicManager,
		"boot: Autoload BackgroundMusic instanciado na raiz")
	if not (autoload is BackgroundMusicManager):
		return
	_manager = autoload
	_check(_manager.get_parent() == root,
		"boot: gerenciador é filho direto do root (posição do Autoload)")
	_check(BackgroundMusicManager.current == _manager,
		"boot: publica referência estática current")
	var players := _music_players()
	_check(players.size() == 1,
		"boot: exatamente 1 reprodutor de música na árvore (veio %d)" % players.size())
	var player := _player()
	_check(player != null, "boot: reprodutor criado")
	if player == null:
		return
	_check(player.bus == BackgroundMusicManager.MUSIC_BUS,
		"boot: player no bus Music (veio %s)" % String(player.bus))
	_check(is_equal_approx(player.volume_db, BackgroundMusicManager.VOLUME_DB),
		"boot: volume de fundo %.1f dB" % player.volume_db)
	_check(player.stream == BackgroundMusicManager.MUSIC_STREAM,
		"boot: toca o asset original da música")
	# Leitura dinâmica do stream DO PLAYER: leitura direta de propriedade
	# em `const` é constant-folding em tempo de compilação no GDScript
	# (valor stale); o caminho dinâmico reflete o estado real do recurso.
	_check((player.stream as AudioStreamMP3).loop,
		"boot: loop habilitado no stream")
	_check(player.process_mode == Node.PROCESS_MODE_ALWAYS,
		"boot: player imune à pausa da árvore (PROCESS_MODE_ALWAYS)")
	_check(player.playing,
		"boot: música iniciada sozinha ao abrir o jogo")
	await _warm_position()
	_check(_last_pos >= WARM_POS,
		"boot: reprodução avança (posição %.3f s)" % _last_pos)


## C) Tela inicial: música segue tocando no menu.
func _case_home_menu() -> void:
	var home: Node = load(HOME_SCENE).instantiate()
	root.add_child(home)
	current_scene = home
	await _frames(8)
	_check(current_scene == home, "menu: cena inicial ativa")
	_check_continuity("menu inicial")


## D) Seleção de fases: a troca home → Levels preserva a trilha.
func _case_levels_screen() -> void:
	change_scene_to_file(LEVELS_SCENE)
	await _frames(30)
	_check(current_scene != null and String(current_scene.name) == "Levels",
		"levels: cena de seleção de fases ativa (veio %s)" % _scene_name())
	_check_continuity("seleção de fases")
	_check(_manager_count() == 1,
		"levels: 1 única instância do gerenciador (veio %d)" % _manager_count())
	_check(_music_players().size() == 1,
		"levels: 1 único reprodutor de música (veio %d)" % _music_players().size())


## E) Partida: música durante o carregamento da fase e com os SFX
## intactos e independentes (bus Master, pool completo, stop_all limpo).
func _case_game_session() -> void:
	change_scene_to_file(GAME_SCENE)
	# Durante o carregamento assíncrono da fase a música já toca.
	await _frames(8)
	_check(current_scene != null and String(current_scene.name) == "Game",
		"game: cena de partida ativa (veio %s)" % _scene_name())
	_check_continuity("carregamento da fase")
	var game = current_scene
	var frames := 0
	if game != null and game.has_method("load_level"):
		while bool(game.get("_loading")) and frames < MAX_WAIT_FRAMES:
			await process_frame
			frames += 1
	_check(game != null and game.has_method("load_level")
			and not bool(game.get("_loading")),
		"game: fase terminou de carregar (%d frames)" % frames)
	await _frames(8)
	_check_continuity("após o carregamento da fase")

	# SFX intactos e independentes da música.
	var sfx := ImpactSoundManager.current
	_check(sfx != null, "sfx: ImpactSoundManager presente na partida")
	if sfx == null:
		return
	_check(sfx._voices.size() == ImpactSoundManager.MAX_VOICES,
		"sfx: pool completo (%d vozes)" % sfx._voices.size())
	var wrong_bus := 0
	for voice in sfx._voices:
		if String(voice.bus) != "Master":
			wrong_bus += 1
	_check(wrong_bus == 0,
		"sfx: vozes permanecem no bus Master (independência da música)")
	# Reprodução real de um SFX com a música ativa.
	sfx.play(ImpactSoundManager.KIND_CANNON_SHOT)
	await physics_frame
	var playing_sfx := 0
	for voice in sfx._voices:
		if voice.playing:
			playing_sfx += 1
	_check(playing_sfx >= 1,
		"sfx: efeito reproduz normalmente com a música ativa")
	# stop_all() da troca de fase não pode tocar na música.
	sfx.stop_all()
	await _frames(4)
	_check_continuity("stop_all dos SFX não afeta a música")


## F) Telas de vitória/derrota: os popups permanecem em game.tscn e a
## trilha atravessa a exibição sem reiniciar.
func _case_victory_defeat_popups() -> void:
	var game = current_scene
	if game == null or not game.has_method("load_level"):
		_check(false, "popup: cena de jogo ativa esperada")
		return
	var popup = game.get("victory_popup")
	if popup == null:
		_check(false, "popup: GamePopup acessível")
		return
	popup.show_popup(0, 0)
	await _frames(4)
	_check(popup.visible, "popup: tela de vitória exibida")
	_check_continuity("durante popup de vitória")
	popup.show_defeat_popup(0, 0)
	await _frames(4)
	_check(popup.visible, "popup: tela de derrota exibida")
	_check_continuity("durante popup de derrota")
	popup.visible = false
	await _frames(2)


## G) Pause (popup de pausa): pausar a árvore não para a trilha.
func _case_pause_popup() -> void:
	paused = true
	await _frames(10)
	_check_continuity("pause (árvore pausada)")
	paused = false
	await _frames(4)


## H) Retry/next da fase (caminhos pós-popup): load_level não reinicia
## a trilha nem troca de cena.
func _case_retry_next() -> void:
	var game = current_scene
	if game == null or not game.has_method("load_level"):
		_check(false, "retry: cena de jogo ativa esperada")
		return
	var next_seed: int = int(game.get("current_seed")) + 1
	var next_level: int = int(game.get("level_number")) + 1
	await game.call("load_level", next_seed, next_level)
	await _frames(8)
	_check(current_scene == game, "retry: sem troca de cena no retry/next")
	_check_continuity("retry/next (load_level da fase)")


## I) Retorno ao menu: nenhuma segunda instância nem segundo player.
func _case_back_to_menu() -> void:
	change_scene_to_file(HOME_SCENE)
	await _frames(12)
	_check(current_scene != null and String(current_scene.name) == "Home",
		"menu: retorno à home (veio %s)" % _scene_name())
	_check(_manager_count() == 1,
		"menu: 1 única instância do gerenciador (veio %d)" % _manager_count())
	_check(_music_players().size() == 1,
		"menu: 1 único reprodutor de música (veio %d)" % _music_players().size())
	_check_continuity("retorno ao menu")


## J) Instância duplicada: descartada antes de criar outro reprodutor
## (nenhuma sobreposição, nenhuma reinicialização).
func _case_duplicate_instance() -> void:
	var before := BackgroundMusicManager.current
	var dup := BackgroundMusicManager.new()
	root.add_child(dup)
	await _frames(3)
	_check(not is_instance_valid(dup),
		"duplicata: instância extra liberada sozinha")
	_check(_manager_count() == 1,
		"duplicata: gerenciador único persiste (veio %d)" % _manager_count())
	_check(_music_players().size() == 1,
		"duplicata: reprodutor único (veio %d)" % _music_players().size())
	_check(BackgroundMusicManager.current == before,
		"duplicata: referência current preservada")
	_check_continuity("duplicata não reinicia a música")


## Aquece a posição de reprodução acima de WARM_POS (driver dummy
## avança em blocos de ~90 ms).
func _warm_position() -> void:
	var player := _player()
	if player == null:
		return
	for i in 90:
		_last_pos = maxf(_last_pos, player.get_playback_position())
		if _last_pos >= WARM_POS:
			return
		await process_frame


## Continuidade: música tocando E posição nunca recuou — um reinício
## faria a posição voltar a ~0, sempre abaixo do máximo já atingido.
func _check_continuity(tag: String) -> void:
	var player := _player()
	_check(player != null and player.playing, "%s: música tocando" % tag)
	if player == null:
		return
	var pos := player.get_playback_position()
	_check(pos >= _last_pos,
		"%s: sem reinício (posição %.3f s >= última %.3f s)" % [tag, pos, _last_pos])
	_last_pos = maxf(_last_pos, pos)


## Todos os AudioStreamPlayer do bus Music em toda a árvore.
func _music_players() -> Array:
	var found: Array = []
	_collect_music_players(root, found)
	return found


func _collect_music_players(node: Node, found: Array) -> void:
	if node is AudioStreamPlayer and \
			(node as AudioStreamPlayer).bus == BackgroundMusicManager.MUSIC_BUS:
		found.append(node)
	for child in node.get_children():
		_collect_music_players(child, found)


func _player() -> AudioStreamPlayer:
	var players := _music_players()
	return players[0] if not players.is_empty() else null


## Instâncias do gerenciador filhas da raiz (posição do Autoload).
func _manager_count() -> int:
	var count := 0
	for child in root.get_children():
		if child is BackgroundMusicManager:
			count += 1
	return count


func _scene_name() -> String:
	return String(current_scene.name) if current_scene != null else "null"


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)
