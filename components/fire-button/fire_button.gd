extends TextureButton
## Cooldown do disparo: bloqueio funcional + indicador visual no próprio
## botão (overlay escuro removido de cima para baixo).
##
## Fonte única de tempo: `_cooldown_remaining`. É dela que derivam tanto o
## bloqueio (`is_on_cooldown`) quanto a cobertura do overlay — os dois são
## atualizados no mesmo frame a partir do mesmo valor e não podem
## dessincronizar.
##
## Quem decide se um disparo vale é o jogo (screens/game.gd:shoot): só um
## disparo realmente aceito chama `begin_cooldown()`. Tentativa recusada
## (sem munição, fase encerrada, em pausa) não inicia o cooldown.

## Duração do cooldown, em segundos.
const COOLDOWN_DURATION := 2.0

@onready var _overlay: ColorRect = $CooldownOverlay

var _cooldown_remaining := 0.0


func _ready() -> void:
	# Sem textura própria no estado disabled: reaproveita a normal para o
	# botão manter a aparência original enquanto o cooldown está ativo.
	texture_disabled = texture_normal
	# Qualquer redimensionamento (resolução/proporção de tela) reposiciona
	# o overlay na hora, sem esperar o próximo frame do _process.
	resized.connect(_sync_overlay)
	_sync_overlay()


func _process(delta: float) -> void:
	if _cooldown_remaining <= 0.0:
		return
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if _cooldown_remaining <= 0.0:
		# Terminou: volta a aceitar acionamentos e o overlay some.
		disabled = false
	_sync_overlay()


## true enquanto o cooldown está ativo.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0


## Inicia o cooldown de COOLDOWN_DURATION s e bloqueia o botão. Chamado
## somente depois que um disparo foi aceito pelo jogo.
func begin_cooldown() -> void:
	_cooldown_remaining = COOLDOWN_DURATION
	disabled = true
	_sync_overlay()


## Zera o cooldown (nova fase): botão e overlay voltam ao normal.
func reset_cooldown() -> void:
	_cooldown_remaining = 0.0
	disabled = false
	_sync_overlay()


## Cobertura do overlay é a fração de tempo restante: completa quando
## restam COOLDOWN_DURATION s e proporcional a cada instante até sumir.
## A base fica presa ao rodapé do botão e o topo desce, revelando o
## botão de cima para baixo.
func _sync_overlay() -> void:
	if _overlay == null:
		return
	var ratio := clampf(_cooldown_remaining / COOLDOWN_DURATION, 0.0, 1.0)
	_overlay.offset_top = size.y * (1.0 - ratio)
