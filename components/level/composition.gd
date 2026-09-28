class_name Composition extends RefCounted
## Documento de intenção de uma fase (docs/plan.md, Etapa 1).
## Coração do composition-first: descreve O DESENHO antes de existir
## qualquer Node — canhão, perfil do floor, alvo, grupos de obstáculos,
## structures e intenção de desafio. O RNG constrói a Composition; o
## validador a lê; o builder a concretiza. Nada aqui instancia cena.
##
## Vocabulário centralizado (espelha docs/plan.md § Análise dos Guides).
## Grupos, papéis e funções usam estes ids; peças sem papel não existem.

# Intenções do canhão (sempre à esquerda; altura/apoio variam).
const CANNON_GROUND := &"ground" # integrado ao plano
const CANNON_PLATFORM := &"platform" # patamar elevado com subida + retorno
const CANNON_PERCH := &"perch" # coluna/torre alta (verticalidade = desafio)

# Perfis do floor (a base contínua sempre existe; o relevo varia).
const FLOOR_FLAT := &"flat" # só a base (canhão ground)
const FLOOR_PLATFORM_L := &"platform_l" # patamar em L (Guide1)
const FLOOR_COLUMN := &"column" # coluna portante (Guide2)
const FLOOR_STEPS := &"steps" # degraus suaves de subida/descida
const FLOOR_NOTCH := &"notch" # degrau alto / plataforma ligada ao piso

# Tipos de grupo de obstáculos (a unidade real de desenho).
const GROUP_WALL := &"wall"
const GROUP_TOWER := &"tower"
const GROUP_BRIDGE := &"bridge"
const GROUP_ROOF := &"roof"
const GROUP_FORTRESS := &"fortress"
const GROUP_CORRIDOR := &"corridor"
const GROUP_GATE := &"gate"

# Funções mecânicas (o que o grupo FAZ no jogo, docs/Levels.md §7).
const MECH_BREAKABLE := &"breakable" # vidro: destruir para abrir caminho
const MECH_WEAR := &"wear" # pedra: cobra o 2º impacto
const MECH_RICOCHET := &"ricochet" # metal: dobra o caminho do disparo
const MECH_FRAME := &"frame" # moldura/anteparo sem função mecânica direta

# Funções do alvo (posição + rotação justificadas pelo desenho).
const TARGET_FOOT := &"foot" # baixo, entre construções, deitado
const TARGET_FORTRESS := &"inside_fortress" # protegido, boca orientada
const TARGET_HIGH := &"high" # alto, exige arco cheio ou ricochete
const TARGET_EXCEPTION := &"exception" # fora da direita: desafio especial

var cannon_position: Vector2 = Vector2(173, 523)
var cannon_scale: Vector2 = Vector2(0.2, 0.2)
var cannon_intent: StringName = CANNON_GROUND
var cannon_support: String = "floor" # id do apoio declarado
var floor_profile: StringName = FLOOR_FLAT
var target_position: Vector2 = Vector2(1000, 360)
var target_rotation: float = 0.0
var target_role: StringName = TARGET_FOOT
var groups: Array[Dictionary] = [] # {type, mechanic, ...} (ver builder)
var structures: Array[Dictionary] = [] # {role, link_a, link_b}
var shot_intent: String = "" # intenção de desafio em texto livre
var tags: Array[StringName] = [] # linhagem compositiva (ex. platform+gate)


## Linhagem legível a partir dos elementos (anti-repetição de desenhos).
func summarize_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append(cannon_intent)
	out.append(floor_profile)
	out.append(target_role)
	for group in groups:
		var kind := StringName(str(group.get("type", "")))
		if kind != &"" and not out.has(kind):
			out.append(kind)
	var mech := Composition.mechanics_used(groups)
	for kind in mech:
		if not out.has(kind):
			out.append(kind)
	tags = out
	return out


## Mecânicas (não-frame) presentes nos grupos.
static func mechanics_used(group_list: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for group in group_list:
		var mechanic := StringName(str(group.get("mechanic", MECH_FRAME)))
		if mechanic != MECH_FRAME and not out.has(mechanic):
			out.append(mechanic)
	return out


func to_dict() -> Dictionary:
	var tag_strings: Array = []
	for tag in tags:
		tag_strings.append(String(tag))
	return {
		"cannon_intent": String(cannon_intent),
		"floor_profile": String(floor_profile),
		"target_role": String(target_role),
		"shot_intent": shot_intent,
		"tags": tag_strings,
	}
