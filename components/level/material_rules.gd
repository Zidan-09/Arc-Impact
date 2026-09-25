class_name MaterialRules extends RefCounted
## Tabela de comportamento por material (Etapa 2, docs/plan.md).
## Isola as regras que o LevelSolver (Etapa 4+) vai consumir, lidas do
## CÓDIGO atual — que é a fonte da verdade:
## - Vidro (`glass_obstacle.gd`): `velocity_retain = 0.85`, 1HP (destrói
##   no 1º impacto), detecção via `Area2D` filho => o projétil ATRAVESSA
##   com `linear_velocity *= 0.85`; não rebate.
## - Pedra (`stone_obstacle.gd`): `velocity_retain = 0.85`, `stoneLife = 2`,
##   `PhysicsMaterial(friction = 0, bounce = 1.0)`. 1º hit: racha e mantém
##   o corpo (rebote parcial do motor); 2º hit: atravessa com `*= 0.85`
##   e libera após 2 `physics_frame` (reaplica a velocidade retida).
## - Metal (`metal_obstacle.gd`): indestrutível (`on_hit_completed = pass`),
##   `PhysicsMaterial(friction = 0, bounce = 1.0)` => rebote emergente do
##   motor, sem atenuação aplicada por código.
##
## Divergências PRD (RN-04) RESOLVIDAS — vale o código:
## - Frágil −15%: OK, código usa 0.85.
## - Equilibrado −30% no 2º hit: código usa 0.85 => tabela usa 0.85.
## - Resistente −5% por atrito: código não atenua (bounce 1.0 puro)
##   => tabela usa 1.0. Sincronizar PRD/GDD na implementação do solver.
##
## Sem física, sem Nodes, sem RNG. Novos materiais entram como nova
## entrada em `_rules()` + novo `ObstacleDefinition.KIND_*`.

const INF_HP := -1 # sentinel de indestrutível (metal)


static func kinds() -> Array[StringName]:
	return [ObstacleDefinition.KIND_GLASS, ObstacleDefinition.KIND_STONE, ObstacleDefinition.KIND_METAL]


static func is_known(kind: StringName) -> bool:
	return _rules().has(kind)


## Regra completa do material ou {} se desconhecido.
## Campos: max_hp (INF_HP = indestrutível), velocity_retain (fator
## aplicado ao atravessar na destruição), bounces (rebate via motor),
## passes_through (projétil atravessa ao destruir em vez de rebotar).
static func get_rule(kind: StringName) -> Dictionary:
	if not _rules().has(kind):
		push_error("MaterialRules: kind desconhecido '%s'." % String(kind))
		return {}
	return _rules()[kind]


static func max_hp(kind: StringName) -> int:
	return int(get_rule(kind).get("max_hp", 0))


static func velocity_retain(kind: StringName) -> float:
	return float(get_rule(kind).get("velocity_retain", 1.0))


static func bounces(kind: StringName) -> bool:
	return bool(get_rule(kind).get("bounces", false))


static func passes_through(kind: StringName) -> bool:
	return bool(get_rule(kind).get("passes_through", false))


## Cena correspondente ao kind — fonte única usada pelo LevelBuilder
## (Etapa 7) e pelo SimulationWorld. Preloads resolvidos no parse.
static func scene_for(kind: StringName) -> PackedScene:
	match kind:
		ObstacleDefinition.KIND_GLASS:
			return preload("res://components/obstacles/glass/glassObstacle.tscn")
		ObstacleDefinition.KIND_STONE:
			return preload("res://components/obstacles/stone/stoneObstacle.tscn")
		ObstacleDefinition.KIND_METAL:
			return preload("res://components/obstacles/metal/metalObstacle.tscn")
	push_error("MaterialRules.scene_for: kind desconhecido '%s'." % String(kind))
	return null


## Tamanho base do colisor em px, escala 1.0 (Etapa 3: usado pelo
## LevelValidator para aproximar o AABB como `base_size * scale`).
## Valores lidos dos .tscn: metal 548x548, pedra 500x500, vidro 952x934
## (hitbox Area2D). Com scale 0.2 (padrão da cena de teste),
## metal ~= 110x110.
static func base_size(kind: StringName) -> Vector2:
	match kind:
		ObstacleDefinition.KIND_GLASS:
			return Vector2(952, 934)
		ObstacleDefinition.KIND_STONE:
			return Vector2(500, 500)
		ObstacleDefinition.KIND_METAL:
			return Vector2(548, 548)
	push_error("MaterialRules.base_size: kind desconhecido '%s'." % String(kind))
	return Vector2.ZERO


static func _rules() -> Dictionary:
	return {
		ObstacleDefinition.KIND_GLASS: {
			"max_hp": 1,
			"velocity_retain": 0.85,
			"bounces": false,
			"passes_through": true,
		},
		ObstacleDefinition.KIND_STONE: {
			"max_hp": 2,
			"velocity_retain": 0.85,
			"bounces": true,
			"passes_through": true,
		},
		ObstacleDefinition.KIND_METAL: {
			"max_hp": INF_HP,
			"velocity_retain": 1.0,
			"bounces": true,
			"passes_through": false,
		},
	}
