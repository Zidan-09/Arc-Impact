class_name PatternLibrary extends RefCounted
## Vocabulário de construção do composition-first (docs/plan.md, Etapa 5).
## Peças parametrizáveis abstraídas dos guides — NUNCA fases prontas.
## A variedade nasce da COMBINAÇÃO (intenção do canhão × perfil do floor
## × função do alvo × grupos × situações mecânicas). Sem RNG próprio:
## recebe o rng do gerador (determinismo por seed). Sem Nodes, sem física.
##
## Progressão por banda (espelha DifficultyTable): 1–3 quebra leve,
## 4+ desgaste, 11+ ricochete. Situações de ricochete (espelho/funil/
## fortaleza) chegam na Etapa 8; até lá, bandas 11+ usam o caminho
## legado (ver FastLevelGenerator).

const GLASS_SCALE := Vector2(0.1, 0.1) # guides: ~95x93
const BLOCK_SCALE := Vector2(0.2, 0.2) # guides: pedra 100, metal ~110

const CANNON_X_SLOTS := [150.0, 200.0, 250.0]
const TARGET_X_SLOTS := [1050.0, 1150.0, 1220.0]
const TARGET_REST_Y := 580.0 # centro do alvo apoiado no plano (620 - 40)
const PERCH_TOPS := [270.0, 370.0]


## Situações mecânicas que a banda permite (docs/Levels.md §7).
static func mechanics_for_level(level_number: int) -> Array[StringName]:
	var out: Array[StringName] = [Composition.MECH_BREAKABLE]
	if level_number >= 4:
		out.append(Composition.MECH_WEAR)
	if level_number >= 11:
		out.append(Composition.MECH_RICOCHET)
	return out


## Material da situação: vidro QUEBRA, pedra DESGASTA, metal RICOCHETEIA.
static func material_for(mechanic: StringName) -> StringName:
	match mechanic:
		Composition.MECH_BREAKABLE:
			return ObstacleDefinition.KIND_GLASS
		Composition.MECH_WEAR:
			return ObstacleDefinition.KIND_STONE
		Composition.MECH_RICOCHET:
			return ObstacleDefinition.KIND_METAL
	return ObstacleDefinition.KIND_STONE


static func scale_for(kind: StringName) -> Vector2:
	if kind == ObstacleDefinition.KIND_GLASS:
		return GLASS_SCALE
	return BLOCK_SCALE


## Intenção do canhão: ground/plataforma baixa no início; perch (coluna
## alta, verticalidade como desafio) a partir da fase 7.
static func pick_cannon_intent(rng: RandomNumberGenerator, level_number: int) -> StringName:
	var options: Array[StringName] = [Composition.CANNON_GROUND, Composition.CANNON_PLATFORM]
	if level_number >= 7:
		options.append(Composition.CANNON_PERCH)
	return options[rng.randi_range(0, options.size() - 1)]


static func pick_cannon_x(rng: RandomNumberGenerator) -> float:
	return CANNON_X_SLOTS[rng.randi_range(0, CANNON_X_SLOTS.size() - 1)]


static func pick_target_x(rng: RandomNumberGenerator) -> float:
	return TARGET_X_SLOTS[rng.randi_range(0, TARGET_X_SLOTS.size() - 1)]


## Rotação com função (pé/entremeio: deitado fecha o tiro rasteiro e
## pede arco por cima, como o Guide1; neutro expõe o flanco).
static func pick_target_rotation(rng: RandomNumberGenerator) -> float:
	return 90.0 if rng.randf() < 0.5 else 0.0


static func pick_perch_top(rng: RandomNumberGenerator) -> float:
	return PERCH_TOPS[rng.randi_range(0, PERCH_TOPS.size() - 1)]
