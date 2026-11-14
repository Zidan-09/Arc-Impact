extends SceneTree
## Regressão da feature: Efeitos Sonoros de Impacto.
##
## Cobre os critérios de aceitação:
##  - cada material usa EXCLUSIVAMENTE os áudios da própria pasta
##    (stone/metal/glass/floor), com os pools certos (5/5/1/5) e
##    nenhuma mistura entre materiais;
##  - variação aleatória: sorteio sem repetir o arquivo imediatamente
##    anterior e com distribuição equilibrada (todos os arquivos
##    aparecem, sem viés de índice);
##  - Glass (arquivo único): pitch aleatório dentro da faixa central
##    configurada, com variação perceptível e sem exagero; os demais
##    materiais ficam no micro-jitter configurado;
##  - reprodução sincronizada com o impacto confirmado: exatamente 1 som
##    por impacto (obstáculo, vidro, chão), sem duplicatas quando os
##    múltiplos caminhos (raio, CCD, sinal do HitBox) veem o mesmo
##    evento, e sem som em Shard/Target;
##  - ricochetes consecutivos na MESMA peça geram som a cada contato
##    novo (contato do CCD antes do dedup por instância), sem spam em
##    repouso;
##  - impactos simultâneos de balas distintas não se suprimem (dedup por
##    frame é POR BALA);
##  - pool fixo de vozes: nunca cria nó por impacto, limite rígido de
##    reproduções simultâneas e stop_all() limpo (troca de fase);
##  - sem gerenciador na cena: no-op sem erro (tests/guides).
##
## Roda headless, sem framework:
##   godot --headless --path . -s res://components/impact-sound/tests/impact_sound_test.gd

const BULLET_SCENE: PackedScene = preload("res://components/bullet/bullet.tscn")
const FLOOR_SCENE: PackedScene = preload("res://components/floor/floor.tscn")

const CELL := 64.0
const OVERLAP := 1.01            # sobreposição 1.01 da arte (floor.tscn)
const TILE := CELL * OVERLAP
const CANNON_SCALE := 0.16
const FAST_SPEED := 2000.0       # shots/game.tscn base_shot_speed
const SPAWN_HEIGHT := 120.0
const MAX_FRAMES := 300

## Pastas exclusivas de cada material (nenhum áudio de outro material).
const FOLDER_BY_MATERIAL: Dictionary = {
	ObstacleDefinition.KIND_STONE: "res://assets/obstacles/stone/",
	ObstacleDefinition.KIND_METAL: "res://assets/obstacles/metal/",
	ObstacleDefinition.KIND_GLASS: "res://assets/obstacles/glass/",
	ImpactTextManager.KIND_FLOOR: "res://assets/floor/",
}

var _failures := 0
var _world: Node2D
var _manager: CountingSoundManager


## Gerenciador instrumentado: registra cada [material, stream] que
## efetivamente entrou numa voz (_start_voice é o único ponto de início
## da reprodução), sem alterar a lógica real.
class CountingSoundManager:
	extends ImpactSoundManager
	var started: Array = []

	func _start_voice(stream: AudioStream, material: StringName) -> void:
		started.append([material, stream])
		super._start_voice(stream, material)


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await physics_frame
	_manager = CountingSoundManager.new()
	root.add_child(_manager)
	_check(ImpactSoundManager.current == _manager,
		"gerenciador publica referência estática em _ready")
	_check(_manager._voices.size() == ImpactSoundManager.MAX_VOICES,
		"pool nasce com %d vozes (veio %d)" % [
			ImpactSoundManager.MAX_VOICES, _manager._voices.size()])

	await _case_assets_and_config()
	await _case_picker_no_repeat_balance()
	await _case_glass_pitch_variation()
	await _case_pool_offsets_and_stop()
	await _case_stone()
	await _case_metal()
	await _case_glass()
	await _case_floor()
	await _case_seam_one_sound()
	await _case_two_bullets_simultaneous()
	await _case_ricochet_consecutive()
	await _case_glass_both_orders()
	await _case_shard_and_target_silent()
	await _case_phase_cleanup()
	await _case_without_manager()

	if _failures == 0:
		print("IMPACT_SOUND_TEST: PASS")
	else:
		printerr("IMPACT_SOUND_TEST: FAIL (%d checagens falharam)" % _failures)
	quit(_failures)


## Pools por material: quantidade certa, cada arquivo EXCLUSIVAMENTE na
## pasta do próprio material, e configurações centralizadas coerentes
## (chave floor compartilhada com o texto, volume final sensato, faixa do
## Glass centrada e sem exagero, offset do Glass no transiente medido).
func _case_assets_and_config() -> void:
	await _begin_case()
	var expected_counts := {
		ObstacleDefinition.KIND_STONE: 5,
		ObstacleDefinition.KIND_METAL: 5,
		ObstacleDefinition.KIND_GLASS: 1,
		ImpactTextManager.KIND_FLOOR: 5,
	}
	for material in expected_counts:
		var pool: Array = ImpactSoundManager.sounds_for(material)
		_check(pool.size() == int(expected_counts[material]),
			"assets: %s tem %d arquivos (veio %d)" % [
				str(material), int(expected_counts[material]), pool.size()])
		var folder: String = FOLDER_BY_MATERIAL[material]
		var all_own := true
		for stream in pool:
			var path := (stream as AudioStream).resource_path
			if not path.begins_with(folder):
				all_own = false
		_check(all_own, "assets: %s usa somente arquivos de %s" % [str(material), folder])

	_check(ImpactSoundManager.KIND_FLOOR == ImpactTextManager.KIND_FLOOR,
		"assets: chave floor compartilhada com o sistema de texto")
	# Fallback: material fora do mapa cai no conjunto do chão.
	var fallback: Array = ImpactSoundManager.sounds_for(&"material_inexistente")
	var floor_pool: Array = ImpactSoundManager.sounds_for(ImpactTextManager.KIND_FLOOR)
	_check(fallback.size() == floor_pool.size() and fallback.size() > 0,
		"assets: material desconhecido cai no pool do chão")

	# Configurações de mixagem (centralizadas no gerenciador).
	_check(ImpactSoundManager.SFX_VOLUME_DB <= 0.0,
		"config: volume global negativo (veio %.1f dB)" % ImpactSoundManager.SFX_VOLUME_DB)
	for material in expected_counts:
		var vol := _manager.volume_for(material)
		_check(vol > -12.0 and vol <= 0.0,
			"config: volume final de %s dentro de (-12, 0] dB (veio %.1f)" % [
				str(material), vol])
	_check(ImpactSoundManager.GLASS_PITCH_MIN < 1.0
			and ImpactSoundManager.GLASS_PITCH_MAX > 1.0,
		"config: faixa do Glass contém 1.0")
	_check(ImpactSoundManager.GLASS_PITCH_MAX - ImpactSoundManager.GLASS_PITCH_MIN <= 0.25,
		"config: faixa do Glass não excessiva (span=%.2f)" % (
			ImpactSoundManager.GLASS_PITCH_MAX - ImpactSoundManager.GLASS_PITCH_MIN))
	var glass_offset := _manager.start_offset_for(ObstacleDefinition.KIND_GLASS)
	_check(glass_offset > 3.0 and glass_offset < 4.0,
		"config: offset do Glass no transiente medido (~3,55s; veio %.2f)" % glass_offset)
	for material in [ObstacleDefinition.KIND_STONE, ObstacleDefinition.KIND_METAL,
			ImpactTextManager.KIND_FLOOR]:
		_check(_manager.start_offset_for(material) == 0.0,
			"config: %s começa em 0.0 (arquivo já inicia no transiente)" % str(material))
	await _settle(2)


## Variação aleatória: 500 sorteios por material com múltiplos arquivos
## — NUNCA repete o anterior, todos os arquivos aparecem e a
## distribuição é equilibrada (sem viés para índices fixos).
func _case_picker_no_repeat_balance() -> void:
	await _begin_case()
	var draws := 500
	for material in [
			ObstacleDefinition.KIND_STONE,
			ObstacleDefinition.KIND_METAL,
			ImpactTextManager.KIND_FLOOR]:
		var pool: Array = ImpactSoundManager.sounds_for(material)
		var counts := {}
		var last: AudioStream = null
		var repeated := 0
		for i in draws:
			var stream := _manager._pick_stream(material)
			if stream == null:
				repeated += 1
				continue
			if stream == last:
				repeated += 1
			last = stream
			counts[stream] = int(counts.get(stream, 0)) + 1
		_check(repeated == 0,
			"sorteio: %s nunca repete o arquivo imediatamente anterior (%d repetições)" % [
				str(material), repeated])
		_check(counts.size() == pool.size(),
			"sorteio: %s usa todos os %d arquivos (%d distintos)" % [
				str(material), pool.size(), counts.size()])
		var min_count := draws
		var max_count := 0
		for stream in counts:
			min_count = mini(min_count, int(counts[stream]))
			max_count = maxi(max_count, int(counts[stream]))
		_check(min_count >= draws / pool.size() / 2,
			"sorteio: %s equilibrado (min=%d, max=%d, esperado~%d)" % [
				str(material), min_count, max_count, draws / pool.size()])
	# Arquivo único: sempre o mesmo (o pitch do Glass cobre a variação).
	for i in 5:
		var glass_stream := _manager._pick_stream(ObstacleDefinition.KIND_GLASS)
		_check(glass_stream != null
				and glass_stream == ImpactSoundManager.sounds_for(
					ObstacleDefinition.KIND_GLASS)[0],
			"sorteio: glass (arquivo único) devolve sempre o mesmo")
	await _settle(2)


## Pitch do Glass: dentro da faixa centralizada, com variação real entre
## reproduções; os demais materiais ficam dentro do micro-jitter.
func _case_glass_pitch_variation() -> void:
	await _begin_case()
	seed(7)  # sequência determinística
	var lo := ImpactSoundManager.GLASS_PITCH_MIN
	var hi := ImpactSoundManager.GLASS_PITCH_MAX
	var values := {}
	var in_range := true
	for i in 40:
		var pitch := _manager.pitch_for(ObstacleDefinition.KIND_GLASS)
		values[snappedf(pitch, 0.0001)] = true
		if pitch < lo or pitch > hi:
			in_range = false
	_check(in_range, "glass: pitch sempre dentro de [%.2f, %.2f]" % [lo, hi])
	_check(values.size() >= 3,
		"glass: pitch varia entre reproduções (%d distintos em 40)" % values.size())

	var jitter := ImpactSoundManager.PITCH_JITTER
	var jitter_ok := true
	var non_glass_values := {}
	for material in [ObstacleDefinition.KIND_STONE, ObstacleDefinition.KIND_METAL,
			ImpactTextManager.KIND_FLOOR]:
		for i in 10:
			var pitch := _manager.pitch_for(material)
			if pitch < 1.0 - jitter or pitch > 1.0 + jitter:
				jitter_ok = false
			non_glass_values[snappedf(pitch, 0.0001)] = true
	_check(jitter_ok, "demais materiais: pitch dentro do jitter ±%.3f" % jitter)
	_check(non_glass_values.size() >= 3,
		"demais materiais: micro-variação de pitch ativa (%d distintos)" %
			non_glass_values.size())
	await _settle(2)


## Pool e mixagem: uma reprodução isolada herda volume/pitch/stream
## corretos; o pool nunca cresce por impacto; a saturação respeita o
## limite rígido; stop_all() zera tudo.
func _case_pool_offsets_and_stop() -> void:
	await _begin_case()
	_manager.stop_all()
	_manager.started.clear()

	# Reprodução isolada: voz única a tocar com os atributos do material.
	_manager.play(ObstacleDefinition.KIND_STONE)
	_check(_manager.started.size() == 1, "pool: play() inicia exatamente 1 voz")
	var playing := _playing_voices()
	_check(playing.size() == 1, "pool: 1 voz tocando após 1 play (veio %d)" % playing.size())
	if playing.size() == 1:
		var voice: AudioStreamPlayer = playing[0]
		var stream_path := voice.stream.resource_path if voice.stream != null else ""
		_check(stream_path.begins_with("res://assets/obstacles/stone/"),
			"pool: voz toca o arquivo do material (%s)" % stream_path)
		_check(is_equal_approx(voice.volume_db, _manager.volume_for(
				ObstacleDefinition.KIND_STONE)),
			"pool: volume aplicado = global + trim (veio %.1f dB)" % voice.volume_db)
		_check(voice.pitch_scale >= 1.0 - ImpactSoundManager.PITCH_JITTER
				and voice.pitch_scale <= 1.0 + ImpactSoundManager.PITCH_JITTER,
			"pool: pitch do material dentro do jitter (veio %.3f)" % voice.pitch_scale)

	# Offset do Glass: a reprodução ENTRA no transiente (3,55s), não no
	# início do arquivo — medição ffmpeg: silêncio até 3,6s.
	_manager.stop_all()
	_manager.play(ObstacleDefinition.KIND_GLASS)
	await physics_frame
	playing = _playing_voices()
	_check(playing.size() == 1, "glass: voz do vidro ativa (veio %d)" % playing.size())
	if playing.size() == 1:
		var pos := (playing[0] as AudioStreamPlayer).get_playback_position()
		_check(pos >= 3.4,
			"glass: reprodução inicia no transiente (posição=%.2fs >= 3.4)" % pos)

	# Saturação: MAX+4 reproduções sem intervalo — nunca acima do pool
	# e nenhum nó novo criado (filhos fixos do gerenciador).
	_manager.stop_all()
	_manager.started.clear()
	var before_children := _manager.get_child_count()
	for i in ImpactSoundManager.MAX_VOICES + 4:
		_manager.play(ObstacleDefinition.KIND_METAL)
	_check(_manager.started.size() == ImpactSoundManager.MAX_VOICES + 4,
		"pool: todas as chamadas processadas (%d)" % _manager.started.size())
	playing = _playing_voices()
	_check(playing.size() <= ImpactSoundManager.MAX_VOICES,
		"pool: no máximo %d vozes simultâneas (veio %d)" % [
			ImpactSoundManager.MAX_VOICES, playing.size()])
	_check(_manager.get_child_count() == before_children,
		"pool: nenhum nó de áudio criado por impacto (filhos=%d)" %
			_manager.get_child_count())

	_manager.stop_all()
	_check(_playing_voices().is_empty(), "stop_all: nenhuma voz tocando")
	await _settle(5)


## Impacto em pedra: exatamente 1 som, arquivo EXCLUSIVAMENTE da pasta
## stone, sem novos sons enquanto a bala se afasta.
func _case_stone() -> void:
	await _begin_case()
	_make_counting_stone(Vector2.ZERO, Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var bounced := false
	for i in MAX_FRAMES:
		await physics_frame
		if is_instance_valid(bullet) and bullet.linear_velocity.y < -1.0:
			bounced = true
			break
		if not is_instance_valid(bullet):
			break
	_check(bounced, "stone: ricochete intacto (física preservada)")
	_check(_manager.started.size() == 1,
		"stone: exatamente 1 som no impacto (veio %d)" % _manager.started.size())
	_assert_plays_folder(ObstacleDefinition.KIND_STONE, "stone")
	await _settle(20)
	_check(_manager.started.size() == 1,
		"stone: sem som extra depois do afasto (veio %d)" % _manager.started.size())


## Impacto em metal: exatamente 1 som, pasta metal.
func _case_metal() -> void:
	await _begin_case()
	_make_counting_metal(Vector2.ZERO, Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var hit_seen := false
	for i in MAX_FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		if _manager.started.size() >= 1:
			hit_seen = true
			break
	_check(hit_seen, "metal: som no impacto")
	_check(_manager.started.size() == 1,
		"metal: exatamente 1 som (veio %d)" % _manager.started.size())
	_assert_plays_folder(ObstacleDefinition.KIND_METAL, "metal")
	await _settle(20)
	_check(_manager.started.size() == 1,
		"metal: sem som extra em repouso (veio %d)" % _manager.started.size())


## Vidro: exatamente 1 som (pasta glass), e os shards gerados após a
## destruição NÃO acrescentam nenhum som.
func _case_glass() -> void:
	await _begin_case()
	_make_counting_glass(Vector2.ZERO)
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var passed := false
	for i in 90:
		await physics_frame
		if not is_instance_valid(bullet):
			break
		if bullet.global_position.y > TILE:
			passed = true
			break
	_check(passed, "glass: bala atravessou o vidro")
	_check(_manager.started.size() == 1,
		"glass: exatamente 1 som no estilhaço (veio %d)" % _manager.started.size())
	_assert_plays_folder(ObstacleDefinition.KIND_GLASS, "glass")
	# Espera os shards caírem/viverem: nenhum som novo por instanciá-los.
	await _settle(40)
	_check(_manager.started.size() == 1,
		"glass: shards não geram som adicional (veio %d)" % _manager.started.size())


## Chão: 1 som no primeiro contato e NENHUM durante o repouso (sem spam
## por frame — mesmo critério do texto).
func _case_floor() -> void:
	await _begin_case()
	_make_floor_tile(Vector2.ZERO)
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	var got := false
	for i in MAX_FRAMES:
		await physics_frame
		if _manager.started.size() >= 1:
			got = true
			break
		if not is_instance_valid(bullet):
			break
	_check(got, "floor: contato gerou som")
	_check(_manager.started.size() == 1,
		"floor: exatamente 1 som no primeiro contato (veio %d)" % _manager.started.size())
	_assert_plays_folder(ImpactTextManager.KIND_FLOOR, "floor")
	var max_seen := _manager.started.size()
	for i in 30:
		await physics_frame
		max_seen = maxi(max_seen, _manager.started.size())
	_check(max_seen == 1,
		"floor: sem spam durante o repouso (máx. observado %d)" % max_seen)


## Junção pedra+pedra: 2 elementos no MESMO contato → 1 único som
## (dedup por frame da bala, mesma regra da onomatopeia).
func _case_seam_one_sound() -> void:
	await _begin_case()
	_make_counting_stone(Vector2(-CELL * 0.5, 0.0), Vector2(TILE, TILE))
	_make_counting_stone(Vector2(CELL * 0.5, 0.0), Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	for i in MAX_FRAMES:
		await physics_frame
		if _manager.started.size() >= 1:
			break
		if not is_instance_valid(bullet):
			break
	_check(_manager.started.size() == 1,
		"junção: 1 som para os 2 elementos simultâneos (veio %d)" % _manager.started.size())
	_assert_plays_folder(ObstacleDefinition.KIND_STONE, "junção")
	await _settle(10)


## Duas balas atingindo 2 obstáculos no mesmo frame: o dedup por frame é
## POR BALA — as duas reproduções acontecem (impactos simultâneos não se
## suprimem).
func _case_two_bullets_simultaneous() -> void:
	await _begin_case()
	_make_counting_stone(Vector2(-CELL * 0.5, 0.0), Vector2(TILE, TILE))
	_make_counting_metal(Vector2(CELL * 0.5, 0.0), Vector2(TILE, TILE))
	var bullet_a := await _spawn_bullet(
		Vector2(-CELL * 0.5, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	var bullet_b := await _spawn_bullet(
		Vector2(CELL * 0.5, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))

	for i in MAX_FRAMES:
		await physics_frame
		if _manager.started.size() >= 2:
			break
		if not is_instance_valid(bullet_a) and not is_instance_valid(bullet_b):
			break
	_check(_manager.started.size() >= 2,
		"simultâneo: 2 balas => 2 sons (veio %d)" % _manager.started.size())
	var materials := {}
	for play in _manager.started:
		materials[play[0]] = true
	_check(materials.has(ObstacleDefinition.KIND_STONE)
			and materials.has(ObstacleDefinition.KIND_METAL),
		"simultâneo: cada bala toca o som do seu material (%s)" % str(materials.keys()))
	await _settle(10)


## Ricochetes consecutivos na MESMA peça: cada contato novo do CCD gera
## som (hook antes do dedup por instância), sem repetição no mesmo tick
## e sem spam — limitado ao número real de bounces.
func _case_ricochet_consecutive() -> void:
	await _begin_case()
	var tile := FLOOR_SCENE.instantiate() as Node2D
	tile.scale = Vector2(0.2, 0.2)
	_world.add_child(tile)

	# Queda vertical sobre o centro do tile (vx=0: todos os bounces na
	# MESMA peça — os sons repetidos vêm do contato do CCD, não de
	# peças novas). Contato inicial ~1600 px/s: CCD sempre engage.
	var bullet := await _spawn_bullet(
		Vector2(0.0, -400.0), Vector2(0.0, 1500.0))

	for i in MAX_FRAMES:
		await physics_frame
		if not is_instance_valid(bullet):
			break
	var plays := _manager.started.size()
	_check(plays >= 2,
		"ricochete: bounces consecutivos na mesma peça soam (veio %d sons)" % plays)
	_check(plays <= 8,
		"ricochete: sem spam — som por contato real, não por frame (%d em %d frames)" % [
			plays, MAX_FRAMES])
	_assert_plays_folder(ImpactTextManager.KIND_FLOOR, "ricochete")
	# Janela em repouso: a bala decresce (e=0,7) até parar — nenhum som
	# novo quando os contatos deixam de acontecer.
	var at_rest := _manager.started.size()
	for i in 40:
		await physics_frame
	_check(_manager.started.size() <= at_rest + 1,
		"ricochete: sem som em repouso (antes=%d, depois=%d)" % [
			at_rest, _manager.started.size()])
	if is_instance_valid(bullet):
		bullet.queue_free()


## Vidro nos DOIS ordens de chegada (sinal próprio x roteador da bala):
## sempre exatamente 1 som — o dedup por instância bloqueia o segundo
## caminho antes do feedback.
func _case_glass_both_orders() -> void:
	# Ordem A: o sinal do HitBox vence.
	await _begin_case()
	var glass_a := _make_counting_glass(Vector2.ZERO)
	var bullet_a := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	glass_a._on_hit_box_body_entered(bullet_a)
	_check(_manager.started.size() == 1,
		"ordem A: sinal próprio => 1 som (veio %d)" % _manager.started.size())
	_assert_plays_folder(&"glass", "ordem A")
	var area_a := glass_a.get_node_or_null("HitBox")
	if area_a != null:
		bullet_a._route_hit(area_a, Vector2.ZERO)
	_check(_manager.started.size() == 1,
		"ordem A: roteador não duplica o som (veio %d)" % _manager.started.size())
	if is_instance_valid(bullet_a):
		bullet_a.queue_free()
	await _settle(3)

	# Ordem B: o roteador vence; o sinal posterior é descartado.
	await _begin_case()
	var glass_b := _make_counting_glass(Vector2.ZERO)
	var bullet_b := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	var area_b := glass_b.get_node_or_null("HitBox")
	if area_b != null:
		bullet_b._route_hit(area_b, Vector2.ZERO)
	_check(_manager.started.size() == 1,
		"ordem B: roteador => 1 som (veio %d)" % _manager.started.size())
	_assert_plays_folder(ObstacleDefinition.KIND_GLASS, "ordem B")
	if is_instance_valid(glass_b):
		glass_b._on_hit_box_body_entered(bullet_b)
	_check(_manager.started.size() == 1,
		"ordem B: sinal não duplica o som (veio %d)" % _manager.started.size())
	if is_instance_valid(bullet_b):
		bullet_b.queue_free()
	await _settle(3)


## Shards e Target nunca geram som (guardas do roteador + isolamento de
## camada): chamadas diretas e passagem real pelo alvo.
func _case_shard_and_target_silent() -> void:
	await _begin_case()
	var scratch: Bullet = BULLET_SCENE.instantiate() as Bullet
	var shard := Shard.new()
	_check(not scratch._route_hit(shard, Vector2.ZERO), "shard: route_hit = false")
	var target := Target.new()
	_check(not scratch._route_hit(target, Vector2.ZERO), "target: route_hit = false")
	_check(_manager.started.size() == 0,
		"shard/target: nenhum som (veio %d)" % _manager.started.size())
	shard.free()
	target.free()
	scratch.free()
	await _settle(2)


## Troca de fase: stop_all() (chamado por game.gd/load_level) zera as
## vozes, e a saída da árvore limpa a referência estática.
func _case_phase_cleanup() -> void:
	await _begin_case()
	_manager.stop_all()
	for i in ImpactSoundManager.MAX_VOICES:
		_manager.play(ObstacleDefinition.KIND_STONE)
	_check(not _playing_voices().is_empty(), "fase: sons tocando antes da troca")
	_manager.stop_all()  # o que game.gd chama em load_level()
	_check(_playing_voices().is_empty(),
		"fase: stop_all() interrompe todos os sons na troca de fase")
	_check(_manager.get_child_count() == ImpactSoundManager.MAX_VOICES,
		"fase: pool permanece estável (nenhum nó órfão)")
	await _settle(2)


## Sem gerenciador na cena (tests/guides): no-op silencioso — a lógica
## de impacto segue intacta e nada de áudio é reproduzido.
func _case_without_manager() -> void:
	await _begin_case()
	_manager.queue_free()
	await physics_frame
	_check(ImpactSoundManager.current == null,
		"sem gerenciador: referência estática limpa em _exit_tree")
	var stone := _make_counting_stone(Vector2.ZERO, Vector2(TILE, TILE))
	var bullet := await _spawn_bullet(
		Vector2(0.0, -TILE * 0.5 - SPAWN_HEIGHT), Vector2(0.0, FAST_SPEED))
	for i in MAX_FRAMES:
		await physics_frame
		if stone.hit_count >= 1 or not is_instance_valid(bullet):
			break
	_check(stone.hit_count == 1,
		"sem gerenciador: hit() segue funcionando (%d)" % stone.hit_count)
	_check(_manager == null or _manager.started.is_empty(),
		"sem gerenciador: nenhum som reproduzido (no-op)")
	_manager = null


## ------------------------------ helpers ------------------------------

func _playing_voices() -> Array:
	var playing: Array = []
	if _manager == null:
		return playing
	for voice in _manager._voices:
		if voice.playing:
			playing.append(voice)
	return playing


## Confere que todos os sons produzidos até aqui saíram da pasta do
## material esperado (nunca mistura materiais).
func _assert_plays_folder(material: StringName, where: String) -> void:
	var folder: String = FOLDER_BY_MATERIAL[material]
	for play in _manager.started:
		var stream := play[1] as AudioStream
		if stream == null or not stream.resource_path.begins_with(folder):
			_check(false, "%s: som de %s veio de pasta alheia (%s)" % [
				where, str(material),
				stream.resource_path if stream != null else "null"])


func _begin_case() -> void:
	await _teardown()
	_world = Node2D.new()
	root.add_child(_world)
	if _manager != null:
		_manager.stop_all()
		_manager.started.clear()


class CountingStone:
	extends StoneObstacle
	var hit_count := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hit_count += 1
		super.hit(bullet, impact_position)


class CountingMetal:
	extends MetalObstacle
	var hit_count := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hit_count += 1
		super.hit(bullet, impact_position)


class CountingGlass:
	extends GlassObstacle
	var hit_count := 0

	func hit(bullet: RigidBody2D, impact_position: Vector2 = Vector2.INF) -> void:
		hit_count += 1
		super.hit(bullet, impact_position)


func _spawn_bullet(pos: Vector2, vel: Vector2) -> Bullet:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.position = pos
	bullet.apply_cannon_scale(Vector2(CANNON_SCALE, CANNON_SCALE))
	bullet.linear_velocity = vel
	# deferred: o _ready da bala cria o trail no pai (padrão do
	# stone_impact_test.gd).
	_world.add_child.call_deferred(bullet)
	await physics_frame
	return bullet


func _make_counting_stone(pos: Vector2, size: Vector2) -> CountingStone:
	var stone := CountingStone.new()
	_add_obstacle_children(stone, size)
	stone.position = pos
	_world.add_child(stone)
	return stone


func _make_counting_metal(pos: Vector2, size: Vector2) -> CountingMetal:
	var metal := CountingMetal.new()
	_add_obstacle_children(metal, size)
	metal.position = pos
	_world.add_child(metal)
	return metal


## Vidro montado como glassObstacle.tscn (Sprite + HitBox Area2D com
## rect), sem depender de texturas no headless.
func _make_counting_glass(pos: Vector2) -> CountingGlass:
	var glass := CountingGlass.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var area := Area2D.new()
	area.name = "HitBox"
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	col.shape = rect
	area.add_child(col)
	glass.add_child(sprite)
	glass.add_child(area)
	glass.position = pos
	_world.add_child(glass)
	return glass


func _add_obstacle_children(body: StaticBody2D, size: Vector2) -> void:
	if body is StoneObstacle:
		var cracked := Sprite2D.new()
		cracked.name = "CrackedStone"
		body.add_child(cracked)
		var polished := Sprite2D.new()
		polished.name = "PolishedStone"
		body.add_child(polished)
	else:
		body.add_child(Sprite2D.new())
	var col := CollisionShape2D.new()
	col.name = "HitBox"
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	body.add_child(col)


func _make_floor_tile(pos: Vector2) -> void:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	col.shape = rect
	body.add_child(col)
	body.position = pos
	_world.add_child(body)


func _settle(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("  [FAIL] " + msg)
	else:
		print("  [ok] " + msg)


func _teardown() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		_world = null
	await physics_frame
