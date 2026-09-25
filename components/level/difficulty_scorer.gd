class_name DifficultyScorer extends RefCounted
## Métrica objetiva de dificuldade (Etapa 8, docs/plan.md §8).
## Dificuldade = medida na solução encontrada, não só contagem de
## blocos. Pesos iniciais a calibrar com playtest; bandas por faixa em
## DifficultyTable. Sem Nodes, sem RNG, sem física.

const W_SHOTS := 3.0
const W_RICOCHETS := 2.0
const W_STONES := 1.5
const W_PRECISION := 1.0
const W_RARITY := 2.0
const W_DISTANCE := 1.0

const SCREEN_DIAGONAL := 1468.6


static func score(def: LevelDefinition, record: SolutionRecord) -> float:
	return float(breakdown(def, record)["total"])


static func breakdown(def: LevelDefinition, record: SolutionRecord) -> Dictionary:
	var stones := stones_destroyed(def, record)
	# Piso na resolução da sonda (±0.5°): margem 0.0 (estreita) vale 4.0,
	# não 100 — sem isso uma solução estreita domina todos os outros
	# termos e nenhuma banda 0..40 a aceitaria (medido na calibragem).
	var margin := maxf(0.25, record.min_angle_margin)
	var rarity := float(maxi(1, record.solutions_found))
	var dist := 0.0
	if def.target != null:
		dist = def.cannon_position.distance_to(def.target.position) / SCREEN_DIAGONAL
	var precision_term := W_PRECISION / margin
	var rarity_term := W_RARITY / rarity
	var total := W_SHOTS * float(record.total_shots) \
		+ W_RICOCHETS * float(record.total_ricochets) \
		+ W_STONES * float(stones) \
		+ precision_term \
		+ rarity_term \
		+ W_DISTANCE * dist
	return {
		"total": total,
		"shots": W_SHOTS * float(record.total_shots),
		"ricochets": W_RICOCHETS * float(record.total_ricochets),
		"stones": W_STONES * float(stones),
		"precision": precision_term,
		"rarity": rarity_term,
		"distance": W_DISTANCE * dist,
		"stones_destroyed": stones,
	}


static func stones_destroyed(def: LevelDefinition, record: SolutionRecord) -> int:
	var kinds := {}
	for obstacle in def.obstacles:
		kinds[obstacle.id] = obstacle.kind
	var seen := {}
	for shot in record.shots:
		for id in Array(shot.get("destroyed", [])):
			if kinds.get(id) == ObstacleDefinition.KIND_STONE:
				seen[id] = true
	return seen.size()


static func in_band(value: float, cfg: DifficultyConfig) -> bool:
	return value >= cfg.score_min and value <= cfg.score_max
