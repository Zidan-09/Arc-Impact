class_name SolutionRecord extends RefCounted
## Solução encontrada pelo LevelSolver para uma fase
## (Etapa 1, docs/plan.md §4.5; solver real na Etapa 5).
## Cada tiro: {"angle": float, "power": float,
##              "ricochets": int, "destroyed": [ids]}.

var shots: Array[Dictionary] = []
var total_shots: int = 0
var total_ricochets: int = 0
var solutions_found: int = 0 # quantas combinações passaram (mede dificuldade)
var min_angle_margin: float = 0.0 # menor perturbação que ainda passa (graus)


func to_dict() -> Dictionary:
	var shot_dicts: Array = []
	for shot in shots:
		shot_dicts.append({
			"angle": float(shot.get("angle", 0.0)),
			"power": float(shot.get("power", 0.0)),
			"ricochets": int(shot.get("ricochets", 0)),
			"destroyed": Array(shot.get("destroyed", [])),
		})
	return {
		"shots": shot_dicts,
		"total_shots": total_shots,
		"total_ricochets": total_ricochets,
		"solutions_found": solutions_found,
		"min_angle_margin": min_angle_margin,
	}


static func from_dict(data: Dictionary) -> SolutionRecord:
	var record := SolutionRecord.new()
	var shot_dicts: Array = data.get("shots", [])
	for shot_data in shot_dicts:
		var shot: Dictionary = shot_data
		record.shots.append({
			"angle": float(shot.get("angle", 0.0)),
			"power": float(shot.get("power", 0.0)),
			"ricochets": int(shot.get("ricochets", 0)),
			"destroyed": Array(shot.get("destroyed", [])),
		})
	record.total_shots = int(data.get("total_shots", 0))
	record.total_ricochets = int(data.get("total_ricochets", 0))
	record.solutions_found = int(data.get("solutions_found", 0))
	record.min_angle_margin = float(data.get("min_angle_margin", 0.0))
	return record
