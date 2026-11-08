class_name ImpactTextManager
extends Node2D
## Gerenciador centralizado das onomatopeias de impacto — a ÚNICA fonte
## de instâncias (nenhum obstáculo controla texto próprio).
##
## Limite rígido: NO MÁXIMO MAX_ACTIVE (3) textos simultâneos, garantido
## de forma SÍNCRONA em `spawn()`: várias colisões no mesmo frame
## (ricochetes em rajada) entram no mesmo call stack, uma a uma, e o
## laço de evicção mantém o invariante antes de cada nova criação — o
## limite nunca é ultrapassado, nem por um frame.
##
## Estrutura: fila FIFO (`_active`, índice 0 = mais antiga). Ao exceder
## o limite, a mais antiga é efetivamente REMOVIDA da árvore
## (`remove_child`, saída imediata — mesmo padrão de
## game.gd/_clear_transient_elements) e liberada (`queue_free`): nada é
## apenas escondido. As entradas já liberadas (animação terminou ou
## fase limpou o grupo) são descartadas no início de `spawn()` — nunca
## por varredura de frame.
##
## Custo por impacto: O(1) amortizado (prune de no máximo 3 entradas),
## UM nó ImpactText (Label puro, sem física) + UM Tween, limitados a 3
## simultâneos. Sem `_process`, sem Timer, sem buscas na árvore de nós:
## a referência é publicada no estático `current` e lida pelo roteador
## da Bullet (`_spawn_impact_text`), zerando custo de descoberta.
##
## O nó fica em `WorldArea/World` (espaço de mundo, acompanha pan/zoom
## da câmera), com transformada identidade — os textos nascem em
## coordenadas globais de mundo. É transiente de fase: os ImpactText
## entram no grupo "impact_texts", que game.gd limpa junto de balas,
## rastros e shards na troca de fase.

## Limite rígido de instâncias simultâneas (requisito da feature).
const MAX_ACTIVE := 3

## Textos possíveis (seleção aleatória por impacto).
const TEXTS: Array[String] = ["POW!", "PEI!", "BAM!", "PÁ!", "TUM!"]

## Deslocamento aleatório em volta do ponto de impacto (px): evita
## sobreposição quando vários impactos acontecem próximos.
const JITTER_X := 16.0
const JITTER_Y := 12.0

## Instância ativa publicada para os produtores (bala). `current` é
## limpo em _exit_tree — troca de cena/home não deixa ponteiro morto.
static var current: ImpactTextManager

## FIFO de textos vivos: índice 0 = mais antiga, a primeira a sair.
var _active: Array[Node] = []


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Cria uma onomatopeia próxima de `impact_pos` respeitando o limite.
## Pode ser chamada várias vezes no mesmo frame (múltiplas colisões);
## a implementação é idempotente com animações em andamento.
func spawn(impact_pos: Vector2) -> void:
	_prune()
	while _active.size() >= MAX_ACTIVE:
		_evict_oldest()
	var text := ImpactText.new()
	add_child(text)
	text.global_position = impact_pos + Vector2(
		randf_range(-JITTER_X, JITTER_X),
		randf_range(-JITTER_Y, JITTER_Y)
	)
	text.play(TEXTS.pick_random())
	_active.append(text)


## Descarta da fila as entradas já liberadas (animação terminou ou a
## limpeza de fase removeu o grupo). Só roda dentro de `spawn()`.
func _prune() -> void:
	for i in range(_active.size() - 1, -1, -1):
		if not is_instance_valid(_active[i]):
			_active.remove_at(i)


## Remove da árvore e libera a mais antiga da fila.
func _evict_oldest() -> void:
	if _active.is_empty():
		return
	var oldest: Node = _active.pop_front()
	if not is_instance_valid(oldest):
		return
	var parent: Node = oldest.get_parent()
	if parent != null:
		parent.remove_child(oldest)
	oldest.queue_free()
