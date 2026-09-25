class_name LevelArchetypeBlockedDirect extends LevelArchetype
## Direta bloqueada: parede de metal atravessando a rota + espelho
## metálico deslocado (motivo de ricochete, fases 11+). Motivo v1, não
## garantia geométrica: quem decide é o solver + o filtro de ricochetes
## mínimos do gerador (rejeita solução sem rebote quando exigido).

func id() -> StringName:
	return &"blocked_direct"


func place(def: LevelDefinition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> bool:
	var before := def.obstacles.size()
	set_target(def, spot_target(rng))
	var wall := mini(3, cfg.metal_count.y)
	if wall < 2:
		rollback(def, before)
		return false
	var from := def.cannon_position
	var to := def.target.position
	var delta := to - from
	var dir := delta / delta.length()
	var normal := Vector2(-dir.y, dir.x)
	var mid := from + delta * 0.5
	# Peças espaçadas 130px: vãos de 20px entre bordas (110px a 0.2)
	# bloqueiam a bala de 92px sem se sobrepor (regra: folga de 8px).
	var offsets := [-130.0, 0.0, 130.0]
	for i in wall:
		var pos: Vector2 = mid + normal * offsets[i]
		if not fits(def, ObstacleDefinition.KIND_METAL, pos, BLOCK_SCALE):
			rollback(def, before)
			return false
		add_ob(def, ObstacleDefinition.KIND_METAL, pos, BLOCK_SCALE)
	# Espelho acima/abaixo da rota, se a cota permitir.
	if def.obstacles.size() - before < cfg.metal_count.y:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var mirror: Vector2 = mid + normal * side * 220.0
		if fits(def, ObstacleDefinition.KIND_METAL, mirror, BLOCK_SCALE):
			add_ob(def, ObstacleDefinition.KIND_METAL, mirror, BLOCK_SCALE)
	return true
