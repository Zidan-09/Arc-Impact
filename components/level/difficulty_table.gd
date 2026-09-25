class_name DifficultyTable extends RefCounted
## Curva de dificuldade por número da fase (Etapa 1, docs/plan.md §4.4).
## Traduz a RN-06 do PRD: fases 1–3 só vidro e tiro direto; 4–10 vidro +
## pedra; 11+ introduz metal bloqueando a reta e exige ricochete.
## Munição decresce com a dificuldade (menos sobra = mais difícil).
## Bandas de score usam a métrica do §8 (pesos e faixas a calibrar na
## Etapa 8). Fases > 20 reutilizam a banda mais difícil (endgame estável)
## com o level_number solicitado preservado.


static func get_config(level_number: int) -> DifficultyConfig:
	var clamped := maxi(level_number, 1)
	for band in _bands():
		if clamped >= int(band["from"]) and clamped <= int(band["to"]):
			return _make_config(clamped, band)
	var hardest: Dictionary = _bands()[_bands().size() - 1]
	return _make_config(clamped, hardest)


static func _bands() -> Array:
	# Bandas calibradas na Etapa 8 com a física real (sonda headless,
	# grade 10°x0.35): tiro aberto típico = 6.2 (largo, 3 soluções) a
	# 8.3 (estreito, margem 0.25); 1 pedra + 1 ricochete + 2 tiros
	# ~= 13. As bandas antigas (ex.: 20-40 no endgame) rejeitavam
	# tudo que o solver realmente produz — por isso o gerador caía
	# em fallback. Margens largas de propósito: a banda corta
	# extremos, não afina a curva (a curva vem de ammo/arquétipos).
	return [
		{
			"from": 1, "to": 3, "ammo": 4, "max_obstacles": 3,
			"glass": Vector2i(0, 2), "stone": Vector2i(0, 0), "metal": Vector2i(0, 0),
			"ricochets": 0, "archetypes": [&"open_shot", &"glass_barrier"],
			"score": Vector2(0.0, 10.0),
		},
		{
			"from": 4, "to": 6, "ammo": 3, "max_obstacles": 5,
			"glass": Vector2i(1, 3), "stone": Vector2i(1, 2), "metal": Vector2i(0, 0),
			"ricochets": 0, "archetypes": [&"open_shot", &"glass_barrier", &"stone_gate"],
			"score": Vector2(5.0, 16.0),
		},
		{
			"from": 7, "to": 10, "ammo": 3, "max_obstacles": 7,
			"glass": Vector2i(2, 4), "stone": Vector2i(1, 3), "metal": Vector2i(0, 1),
			"ricochets": 0, "archetypes": [&"glass_barrier", &"stone_gate", &"combo_order"],
			"score": Vector2(6.0, 20.0),
		},
		{
			"from": 11, "to": 15, "ammo": 3, "max_obstacles": 9,
			"glass": Vector2i(1, 3), "stone": Vector2i(1, 3), "metal": Vector2i(1, 3),
			"ricochets": 1, "archetypes": [&"blocked_direct", &"stone_gate", &"combo_order", &"bunker"],
			"score": Vector2(9.0, 26.0),
		},
		{
			"from": 16, "to": 20, "ammo": 2, "max_obstacles": 12,
			"glass": Vector2i(1, 4), "stone": Vector2i(2, 4), "metal": Vector2i(2, 4),
			"ricochets": 2, "archetypes": [&"blocked_direct", &"bunker", &"combo_order"],
			"score": Vector2(11.0, 32.0),
		},
	]


static func _make_config(level_number: int, band: Dictionary) -> DifficultyConfig:
	var cfg := DifficultyConfig.new()
	cfg.level_number = level_number
	cfg.ammo = int(band["ammo"])
	cfg.max_obstacles = int(band["max_obstacles"])
	cfg.glass_count = band["glass"]
	cfg.stone_count = band["stone"]
	cfg.metal_count = band["metal"]
	cfg.required_ricochets_min = int(band["ricochets"])
	cfg.allowed_archetypes.clear()
	for archetype in Array(band["archetypes"]):
		cfg.allowed_archetypes.append(archetype)
	# Etapa 9 (benchmark 2026-09-25, física tempo real ~745ms/sim):
	# grade fina (2.0x0.1 = 416 sims/candidato ≈ 5 min) inviabiliza a
	# geração; grade grossa (10x0.35 = ~33 sims, ~8s típico) é o viável
	# na v1 com loading assíncrono. Grade fina volta com física acelerada.
	cfg.solver_angle_step = 10.0
	cfg.solver_power_step = 0.35
	var score: Vector2 = band["score"]
	cfg.score_min = score.x
	cfg.score_max = score.y
	return cfg
