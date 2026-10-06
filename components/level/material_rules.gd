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


## Tamanho base do colisor em px, escala 1.0. Deve casar EXATAMENTE com
## a arte e o shape da cena (quadrado perfeito após `cell_scale_for`):
## metal 547x547 (= metal_square.jpg), pedra 500x500, vidro 952x935
## (= glass_square.jpg, hitbox Area2D). A escala de instanciação é
## `GridState.cell_scale_for(base)` => colisão exata de CELL_SIZE.
static func base_size(kind: StringName) -> Vector2:
	match kind:
		ObstacleDefinition.KIND_GLASS:
			return Vector2(952, 935)
		ObstacleDefinition.KIND_STONE:
			return Vector2(500, 500)
		ObstacleDefinition.KIND_METAL:
			return Vector2(547, 547)
	push_error("MaterialRules.base_size: kind desconhecido '%s'." % String(kind))
	return Vector2.ZERO


## Tamanho base do sprite da Structure em px, escala 1.0 (Etapa 2 da
## refatoração composition-first). Medido de
## `assets/structure/structure.png` (482x448); em scale 0.15 (guides)
## ~= 72x67. Rotação 90° troca largura/altura, como nos obstáculos.
static func structure_size() -> Vector2:
	return Vector2(482, 448)


## Tamanho base do tile do Floor em px, escala 1.0 (Etapa 2). Lido de
## `components/floor/floor.tscn` (RectangleShape2D 500x500, sprite
## `assets/floor/floor.png` 500x500); em scale 0.2 = tile 100x100, a
## unidade da grade dos guides.
static func floor_size() -> Vector2:
	return Vector2(500, 500)


## Tamanho base do alvo em px, escala 1.0 (docs/plan.md §5 item 6:
## fonte única do tamanho do alvo). Pós-correção do item 5: polígono
## alargado para casar com o visual (~144x474 base → ~28.8x94.8 @0.2;
## era 114x474 antes do alargamento de 3px/lado instanciados).
## `LevelValidator._target_rect` e `FastLevelGenerator.target_body()`
## derivam daqui; a cena é a materialização do mesmo número.
static func target_size() -> Vector2:
	return Vector2(144, 474)


## Escala fixa do Target na cena (raiz de target.tscn, sempre 0.2 —
## o builder nunca sobrescreve; ver docs/plan.md §2).
static func target_scale() -> Vector2:
	return Vector2(0.2, 0.2)


## Corpo instanciado do alvo em px (para validador e solver analítico).
static func target_body_size() -> Vector2:
	return target_size() * target_scale()


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
