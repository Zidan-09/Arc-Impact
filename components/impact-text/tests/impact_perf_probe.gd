extends SceneTree
## Sonda de performance do Sistema de Onomatopeias nos Impactos.
##
## Mede o custo por frame do sistema em duas condições:
##  1. baseline: nenhum ImpactText vivo;
##  2. carga: 1 spawn por frame (o limite de 3 mantém sempre 3 textos
##     animando — cenário de pior caso real, rajada de impactos).
## Também mede o custo de um burst de spawns no MESMO frame (o caminho
## de múltiplas colisões simultâneas) e confirma que o nº de nós vivo
## nunca ultrapassa 3. Sem GPU: headless mede lógica + Tween + layout
## do Label, que é o custo que a feature agrega à CPU.
## Uso: godot --headless --path . -s res://components/impact-text/tests/impact_perf_probe.gd


const FRAMES := 300
const WARMUP := 60


func _initialize() -> void:
	await physics_frame
	var manager := ImpactTextManager.new()
	root.add_child(manager)

	# Aquecimento: primeiro spawn paga criação de nó/fonte (pico único,
	# igual ao pico do primeiro disparo já conhecido no projeto).
	for i in WARMUP:
		manager.spawn(Vector2(float(i), 0.0))
		await process_frame
	await _settle(manager)

	var baseline := await _measure(manager, false)
	var load := await _measure(manager, true)

	# Burst: 12 spawns no MESMO frame (o pior caso de colisões em rajada).
	var burst_start := Time.get_ticks_usec()
	for i in 12:
		manager.spawn(Vector2(float(i), 100.0))
	var burst_us := float(Time.get_ticks_usec() - burst_start)
	var alive := _alive(manager)
	await _settle(manager)

	print("condicao        | frames | ms/frame medio | p95 ms | FPS equivalente")
	_print_row("baseline", baseline)
	_print_row("carga (3 ativos)", load)
	print("burst 12 spawns no mesmo frame: %.0f us total (%.0f us/spawn)" % [
		burst_us, burst_us / 12.0])
	print("nos vivos apos burst (limite 3): %d" % alive)
	print("delta carga vs baseline: %+.3f ms/frame" % [
		load["avg"] - baseline["avg"]])
	quit(0)


## Roda FRAMES frames medindo o tempo de cada process frame. Com
## `spawning`, cria 1 texto por frame (mantém 3 simultâneos).
func _measure(manager: ImpactTextManager, spawning: bool) -> Dictionary:
	var samples: Array[float] = []
	for i in FRAMES:
		if spawning:
			manager.spawn(Vector2(float(i % 64), float(i % 48)))
		var t0 := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	var total := 0.0
	for s in samples:
		total += s
	return {
		"avg": total / samples.size(),
		"p95": samples[int(samples.size() * 0.95)],
	}


func _print_row(label: String, m: Dictionary) -> void:
	print("%-15s | %6d | %14.3f | %6.3f | %6.1f" % [
		label, FRAMES, m["avg"], m["p95"],
		1000.0 / maxf(m["avg"], 0.001)])


## Espera os textos terminarem (Tween 0.55s + folga) e os liberarem.
func _settle(manager: ImpactTextManager) -> void:
	for i in 90:
		await process_frame
		if _alive(manager) == 0:
			return


func _alive(manager: ImpactTextManager) -> int:
	var n := 0
	for c in manager.get_children():
		if c is ImpactText:
			n += 1
	return n
