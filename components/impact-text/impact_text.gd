class_name ImpactText
extends Node2D
## Onomatopeia de impacto (feature: Sistema de Onomatopeias nos Impactos).
##
## Nó puramente visual: Node2D + Label, SEM física (nenhum CollisionShape,
## nenhuma camada/monitoring) e sem `_process`/`_physics_process`. A vida
## útil é controlada por UM Tween criado em `play()`, vinculado ao nó —
## morre com ele, sem Timer e sem polling de duração (§5 performance).
##
## Identidade visual Arc-Impact: texto branco, fonte quadrada arcade
## (Press Start 2P — assets/fonts, reuso de recurso novo pois o projeto
## não tinha fonte), contorno escuro fino para legibilidade sobre o
## cenário neon, leve rotação aleatória mantida fixa na animação.
## O deslocamento aleatório em volta do ponto de impacto é aplicado pelo
## gerenciador (ImpactTextManager.spawn) antes de `play()`.
##
## Animação (uma única timeline, ~0.55 s):
##  - entrada: escala START_SCALE -> 1.0 com overshoot sutil (TRANS_BACK);
##  - permanência: subida suave de RISE_DISTANCE durante a vida toda,
##    com a rotação permanecendo a definida na spawn;
##  - saída: fade-out (modulate:a -> 0) combinado com encolhimento e,
##    ao fim, `queue_free()` — o nó sai da árvore e libera o Label junto.

## Fonte arcade quadrada (SIL OFL 1.1 — assets/fonts/OFL.txt).
const FONT := preload("res://assets/fonts/PressStart2P-Regular.ttf")

## Identidade/medidas em px de mundo: font_size 32 => "POW!" ocupa
## 128x32 — destaque na ação sem dominar a tela (célula de 128 px).
## A caixa do Label é fixa e centralizada na
## origem do nó, para escala/rotação da raiz girarem em volta do ponto
## de impacto (pivot natural do Node2D, sem pivot de Control).
const FONT_SIZE := 32
const LABEL_SIZE := Vector2(224.0, 58.0)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)
const OUTLINE_SIZE := 6

## Tempos da animação (s). Total curto (LIFETIME): leitura rápida sem
## poluir a tela nem atrapalhar a jogabilidade.
const ENTRY_TIME := 0.10
const EXIT_TIME := 0.16
const LIFETIME := 0.55

## Escala inicial da entrada (ligeiramente menor que o normal) e
## escala final da saída (combina com o fade para reforçar o impacto).
const START_SCALE := 0.6
const SHRINK_SCALE := 0.75

## Distância da subida suave durante a permanência (px).
const RISE_DISTANCE := 40.0

## Inclinação aleatória máxima (graus): nunca "perfeitamente reto".
const MAX_ROTATION_DEG := 10.0

## Desenho acima dos elementos do mundo (rastros z=1, balas z=2).
const Z_INDEX := 5

## Grupo transitório: game.gd limpa "impact_texts" na troca de fase,
## junto de balas/rastros/shards (mesmo sistema de _clear_transient).
const GROUP_NAME := "impact_texts"

var _label: Label


func _ready() -> void:
	z_index = Z_INDEX
	add_to_group(GROUP_NAME)
	_label = Label.new()
	_label.size = LABEL_SIZE
	# Centraliza a caixa na origem do nó (o ponto de impacto).
	_label.position = -LABEL_SIZE * 0.5
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Pura decoração: nunca pode consumir cliques/toques — mira e
	# câmera do jogo dependem de _unhandled_input sem interferência.
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	add_child(_label)


## Inicia o ciclo de vida completo. O gerenciador define `position`
## (com deslocamento aleatório) ANTES de chamar: a subida é calculada a
## partir dele. Uma chamada por nó — cada impacto cria um nó novo.
func play(text: String) -> void:
	_label.text = text
	rotation_degrees = randf_range(-MAX_ROTATION_DEG, MAX_ROTATION_DEG)
	scale = Vector2.ONE * START_SCALE
	var rise_target := position + Vector2(0.0, -RISE_DISTANCE)

	var tween := create_tween()
	# Entrada: escala rápida com overshoot sutil (elástico, EASE_OUT).
	tween.tween_property(self, "scale", Vector2.ONE, ENTRY_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Permanência: subida suave ao longo de toda a vida (paralela à
	# entrada); a rotação não é animada — permanece a definida acima.
	tween.parallel().tween_property(self, "position", rise_target, LIFETIME)
	# Espera antes da saída: o tempo de leitura acontece aqui.
	tween.tween_interval(LIFETIME - ENTRY_TIME - EXIT_TIME)
	# Saída: fade-out + redução de escala, reforçando a sensação de
	# impacto sem sumir de forma abrupta.
	tween.tween_property(self, "modulate:a", 0.0, EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale",
		Vector2.ONE * SHRINK_SCALE, EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Fim: sai da árvore de nós (libera Label e o próprio Tween junto).
	# O Tween é vinculado a este nó e morre com ele — sem recursos órfãos.
	tween.tween_callback(queue_free)
