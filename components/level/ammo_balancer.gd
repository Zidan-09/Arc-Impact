class_name AmmoBalancer extends RefCounted
## Balanceamento CENTRAL da munição por fase (RN-03 do PRD: 1 a 4).
##
## Ponto único que responde "quanta munição esta fase recebe?". O
## gerador (`GridLevelGenerator`), os testes e qualquer consumidor leem
## daqui — gerador e balanceamento nunca trabalham com parâmetros
## diferentes (a mesma munição que balanceia é a que valida).
##
## Fórmula:
##
##   ammo = clamp(banda.ammo + complexidade(grid), MIN_AMMO, MAX_AMMO)
##
## - `banda.ammo` (`DifficultyTable`) é o PATAMAR do cenário simples
##   da banda: a progressão continua dona da dificuldade base (generoso
##   no tutorial, apertado no endgame);
## - `complexidade(grid)` mede o CENÁRIO REAL gerado — não o número da
##   fase: o custo do caminho que o solver já provou e a exigência de
##   rota indireta. Cenário complexo ganha os tiros que a complexidade
##   cobra; cenário simples fica no patamar da banda;
## - o clamp mantém a RN-03 (1..4): o teto não é removido.
##
## Antes disso, a munição era um número fixo por banda (a mais difícil
## valia 2 para SEMPRE, inclusive no endgame >20): dificuldade por
## escassez de munição, independente do cenário. Aqui a dificuldade
## continua vindo da progressão + complexidade, e a munição cobre o que
## a fase exige.
##
## Invariante: sempre que o caminho comprovado cabe no teto da RN-03
## (`min_cost <= MAX_AMMO`), `ammo >= min_cost` — a fase é solucionável
## com a munição concedida, e o validador confirma com a MESMA munição.

const MIN_AMMO := 1 # RN-03 (PRD §4.2): piso de projéteis por partida
const MAX_AMMO := 4 # RN-03 (PRD §4.2): teto de projéteis por partida


## Patamar da banda para um cenário simples (progressão por fase).
static func baseline_for(level_number: int) -> int:
	return DifficultyTable.get_config(level_number).ammo


## Complexidade do cenário construído, em tiros extras sobre o patamar.
## `arcs` são as métricas de `GridLevelValidator.sample_arcs` (amostradas
## com MAX_AMMO, para não depender da munição final).
static func complexity(grid: GridState, arcs: Dictionary) -> int:
	# 1) Custo do caminho comprovado: `min_cost` tiros — 1 + pedras no
	#    caminho (vidro atravessa no mesmo disparo; ricochete não custa
	#    munição). Cenário de tiro limpo custa 1 => 0 extra.
	var extra := maxi(int(arcs.get("min_cost", 0)), 1) - 1
	# 2) Rota indireta obrigatória: metal (indestrutível) cruza a reta
	#    canhão→alvo => só passa rebatendo ou achar janela fora da reta.
	#    Execução mais precisa pede uma tentativa extra.
	if GridState.Cell.METAL in GridLevelValidator.direct_kinds(grid):
		extra += 1
	return extra


## Munição final de uma fase. `baseline` é o patamar da banda (use
## `baseline_for(level_number)` quando não houver um DifficultyConfig em
## mãos); `arcs` pode vir vazio — aí é amostrado aqui mesmo.
static func ammo_for(grid: GridState, arcs: Dictionary, baseline: int) -> int:
	var metrics := arcs
	if metrics.is_empty():
		metrics = GridLevelValidator.sample_arcs(grid, MAX_AMMO)
	return clampi(baseline + complexity(grid, metrics), MIN_AMMO, MAX_AMMO)
