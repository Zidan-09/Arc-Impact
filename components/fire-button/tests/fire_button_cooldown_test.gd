extends SceneTree
## Regressão do cooldown de 2 s do botão de disparo (screens/game.gd +
## components/fire-button/fire_button.gd). Cenários:
##  1. um disparo aceito inicia o cooldown e o botão é bloqueado;
##  2. tentativas repetidas (programáticas e por clique real) durante o
##     cooldown não acionam o botão (`pressed`), não disparam e não
##     consomem munição;
##  3. o escurecimento cobre o botão inteiro e recua de cima para baixo,
##     sempre proporcional ao tempo restante — mesma referência de tempo
##     do bloqueio — aplicado pelo shader sobre a silhueta do próprio
##     sprite (nada de escuro vaza para fora das bordas arredondadas);
##  4. a máscara acompanha qualquer tamanho do botão (diferentes
##     resoluções/proporções) e some por completo ao fim do cooldown;
##  5. ao completar ~2 s o botão volta a aceitar disparos;
##  6. disparo recusado (sem munição, fase encerrada, em pausa) NÃO
##     inicia o cooldown.
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/fire-button/tests/fire_button_cooldown_test.gd
## Saída: "FIRE_BUTTON_COOLDOWN_TEST: PASS" (exit 0) ou FAIL (exit 1).

const GAME_SCENE := preload("res://screens/game.tscn")
const OVERLAY_NAME := "CooldownOverlay"
const DURATION := 2.0
const MAX_WAIT_FRAMES := 600
## Limite de espera do cooldown (a duração real fica ~2 s; a folga cobre
## lentidão da máquina sem mascarar um cooldown que nunca termina).
const TIMEOUT_MS := 20000
## Tolerância da cobertura (fração revelada no shader) contra o tempo
## restante.
const RATIO_TOLERANCE := 0.05

var _failures := 0
## Acionamentos reais do botão (sinal `pressed`), para provar que o
## botão ignora o acionamento e não apenas o resultado.
var _pressed_count := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# O loop só começa a rodar depois do _init; process_frame garante que
	# root esteja pronto antes de instanciar a cena de jogo.
	await process_frame
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	if not await _wait_level_loaded(game):
		printerr("FIRE_BUTTON_COOLDOWN_TEST: FAIL (a fase inicial não terminou de carregar)")
		quit(1)
		return
	await _run_scenarios(game)
	game.queue_free()
	if _failures == 0:
		print("FIRE_BUTTON_COOLDOWN_TEST: PASS")
	else:
		printerr("FIRE_BUTTON_COOLDOWN_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


func _run_scenarios(game) -> void:
	var button = game.fire_button
	var overlay := button.get_node(OVERLAY_NAME) as Control
	var mask := button.get_node(OVERLAY_NAME + "/CooldownMask") as TextureRect
	button.pressed.connect(_on_button_pressed)

	# Vitória/derrota desligadas para o teste: uma bala acertando o alvo
	# durante os cenários bloquearia os disparos seguintes (game_over).
	if game.current_target != null and game.current_target.target_hit.is_connected(game._on_target_hit):
		game.current_target.target_hit.disconnect(game._on_target_hit)

	# Estado inicial: liberado, overlay oculto e ancorado ao próprio botão.
	await process_frame
	_check(not button.is_on_cooldown(), "inicial: sem cooldown")
	_check(not bool(button.disabled), "inicial: botão habilitado")
	_check(_reveal_frac(mask) == 1.0, "inicial: nenhuma cobertura (tudo revelado)")
	_check(overlay.anchor_right == 1.0 and overlay.anchor_bottom == 1.0,
		"inicial: overlay ancorado ao botão (não à viewport)")
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"inicial: overlay não intercepta cliques")
	_check(overlay.clip_children == Control.CLIP_CHILDREN_DISABLED,
		"inicial: sem recorte de pai (o shader faz o recorte do escuro)")
	_check(mask != null and mask.material is ShaderMaterial
		and (mask.material as ShaderMaterial).shader != null
		and String((mask.material as ShaderMaterial).shader.code).contains("reveal_frac"),
		"inicial: máscara com shader de revelação")
	_check(mask != null and mask.texture == button.texture_normal,
		"inicial: máscara usa o próprio sprite do botão")
	_check(mask != null and mask.stretch_mode == button.stretch_mode
		and mask.expand_mode == TextureRect.EXPAND_IGNORE_SIZE
		and bool(button.ignore_texture_size),
		"inicial: máscara tem o mesmo ajuste de escala do botão")
	_check(mask != null and mask.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"inicial: máscara não intercepta cliques")
	_check(mask != null and _mask_aligned(button, overlay, mask),
		"inicial: máscara exatamente sobre o retângulo do botão")

	# Munição controlada pelo teste (o balanceamento do jogo não muda).
	game.ammo_left = 10
	game._awaiting_end = false
	var ammo0: int = game.ammo_left

	# 1) Disparo aceito inicia o cooldown e cobre o botão por completo.
	var t_shot := Time.get_ticks_msec()
	game.call("shoot")
	_check(int(game.ammo_left) == ammo0 - 1, "disparo aceito consumiu exatamente 1 munição")
	_check(button.is_on_cooldown(), "disparo aceito iniciou o cooldown")
	_check(bool(button.disabled), "botão bloqueado durante o cooldown")
	_check(_reveal_frac(mask) == 0.0, "escuro cobre o botão inteiro imediatamente após o disparo")

	# 2) Tentativas repetidas logo depois: nada dispara.
	var bullets_first := get_nodes_in_group("bullets").size()
	for i in 10:
		game.call("shoot")
	await process_frame
	_check(int(game.ammo_left) == ammo0 - 1, "10 tentativas seguidas: munição intacta")
	_check(get_nodes_in_group("bullets").size() <= bullets_first,
		"10 tentativas seguidas: nenhuma bala extra")

	# 3) Clique real no botão durante o cooldown é ignorado por completo:
	#    nem o sinal `pressed` é emitido (botão desabilitado).
	_click(button)
	await process_frame
	_check(_pressed_count == 0, "clique real durante o cooldown: botão não emite `pressed`")
	_check(int(game.ammo_left) == ammo0 - 1, "clique real durante o cooldown: sem disparo")

	# 4) Sincronia overlay x tempo restante após ~0.4 s.
	await _wait_seconds(0.4)
	_check(button.is_on_cooldown(), "cooldown segue ativo 0.4 s após o disparo")
	_check(_reveal_matches(button, mask), "escurecimento proporcional ao tempo restante")
	_check(_reveal_frac(mask) > 0.0 and _reveal_frac(mask) < 1.0,
		"escuro recua de cima para baixo (topo revelado, base coberta)")
	_check(_mask_aligned(button, overlay, mask),
		"máscara segue exatamente sobre o botão durante a revelação")

	# 5) Redimensionamento no meio do cooldown mantém a proporção.
	button.size = Vector2(64.0, 128.0)
	await process_frame
	_check(_reveal_matches(button, mask), "escurecimento proporcional após redimensionar (64x128)")
	_check(_mask_aligned(button, overlay, mask),
		"máscara realinhada após redimensionar (64x128)")

	# 6) Ao completar ~2 s o botão volta a aceitar disparos.
	while button.is_on_cooldown() and Time.get_ticks_msec() - t_shot < TIMEOUT_MS:
		await process_frame
	var total := float(Time.get_ticks_msec() - t_shot) / 1000.0
	_check(not button.is_on_cooldown(), "cooldown terminou após ~2 s")
	_check(total >= DURATION - 0.2 and total <= DURATION + 1.0,
		"duração do cooldown ≈ 2 s (medido %.2f s)" % total)
	_check(not bool(button.disabled), "botão reabilitado após o cooldown")
	_check(_reveal_frac(mask) == 1.0, "escuro desapareceu por completo")

	# 7) Controle positivo: clique real aciona e dispara de novo.
	var ammo1: int = game.ammo_left
	_click(button)
	await process_frame
	_check(_pressed_count == 1, "clique real após o cooldown: botão aciona normalmente")
	_check(int(game.ammo_left) == ammo1 - 1, "clique real após o cooldown dispara normalmente")
	_check(button.is_on_cooldown(), "novo disparo reiniciou o cooldown")
	button.reset_cooldown()

	# 8) Disparo recusado não inicia o cooldown.
	game.ammo_left = 0
	game._awaiting_end = false
	game.call("shoot")
	_check(not button.is_on_cooldown(), "sem munição: cooldown não inicia")
	_check(not bool(button.disabled), "sem munição: botão não é bloqueado")
	_check(_reveal_frac(mask) == 1.0, "sem munição: escuro continua oculto")

	game.ammo_left = 10
	game.game_over = true
	game.call("shoot")
	_check(not button.is_on_cooldown(), "fase encerrada: cooldown não inicia")
	game.game_over = false

	game._is_paused = true
	game.call("shoot")
	_check(not button.is_on_cooldown(), "em pausa: cooldown não inicia")
	game._is_paused = false


## Espera a fase terminar de carregar (build assíncrono no _ready).
func _wait_level_loaded(game) -> bool:
	var frames := 0
	while bool(game._loading) and frames < MAX_WAIT_FRAMES:
		await process_frame
		frames += 1
	return not bool(game._loading)


## Espera tempo real de relógio (o cooldown conta tempo de frame, não
## quantidade de frames — headless roda muito acima de 60 fps).
func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


## A cobertura aplicada ao shader tem de ser igual à fração de tempo
## restante — é o que garante animação e bloqueio sincronizados.
func _reveal_matches(button, mask: TextureRect) -> bool:
	var ratio := clampf(float(button._cooldown_remaining) / DURATION, 0.0, 1.0)
	var expected := 1.0 - ratio
	return absf(_reveal_frac(mask) - expected) <= RATIO_TOLERANCE


## Fração do botão que está revelada (sem escuro), lida do shader da
## máscara. NAN = sem material/shader — qualquer comparação falha.
func _reveal_frac(mask: TextureRect) -> float:
	var mat := mask.material as ShaderMaterial
	if mat == null:
		return NAN
	var value: Variant = mat.get_shader_parameter("reveal_frac")
	if value == null:
		return NAN
	return float(value)


## A máscara tem de permanecer exatamente sobre o retângulo do botão em
## qualquer ponto da revelação: a geometria é estática (máscara colada no
## retângulo inteiro), então o enquadramento do sprite — e portanto a
## silhueta arredondada que segura o escuro — nunca muda.
func _mask_aligned(button, overlay: Control, mask: Control) -> bool:
	var pos_in_button: Vector2 = overlay.position + mask.position
	return pos_in_button.length() <= 0.01 \
		and mask.size.distance_to(button.size) <= 0.01


## Simula um clique real (movimento + pressiona + solta) no centro do
## botão, nas coordenadas de viewport que o GUI do jogo enxerga.
func _click(button) -> void:
	var viewport_pos: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	_push_mouse(viewport_pos, InputEventMouseMotion.new())
	_push_mouse(viewport_pos, _mouse_button(true))
	_push_mouse(viewport_pos, _mouse_button(false))


func _mouse_button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _push_mouse(viewport_pos: Vector2, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		button_event.position = viewport_pos
		button_event.global_position = viewport_pos
	else:
		var motion_event := event as InputEventMouseMotion
		motion_event.position = viewport_pos
		motion_event.global_position = viewport_pos
	# Coordenadas locais do viewport (canvas), as mesmas de
	# get_global_transform_with_canvas() e de event.position no jogo. Sem
	# isso a posição seria tratada como de janela e o stretch (canvas_items)
	# a levaria fora do botão — em headless a janela raiz é 64x64.
	root.push_input(event, true)


func _on_button_pressed() -> void:
	_pressed_count += 1


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)
