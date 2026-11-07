extends TextureButton
## Cooldown do disparo: bloqueio funcional + indicador visual no próprio
## botão (o próprio sprite escurecido, revelado de cima para baixo).
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

## Parâmetro do shader da máscara: fração do botão já revelada, contada do
## topo. 1.0 = botão inteiro revelado (nenhum escuro); 0.0 = cobertura
## total. O shader zera o fragmento acima dessa linha — o escuro recua de
## cima para baixo sem depender de recorte de pai nem de geometria que
## anda (ambos se mostraram frágeis; o shader roda em qualquer contexto).
const REVEAL_PARAM := &"reveal_frac"

@onready var _mask: TextureRect = $CooldownOverlay/CooldownMask

var _cooldown_remaining := 0.0
var _reveal_material: ShaderMaterial


func _ready() -> void:
	# Sem textura própria no estado disabled: reaproveita a normal para o
	# botão manter a aparência original enquanto o cooldown está ativo.
	texture_disabled = texture_normal
	_reveal_material = _mask.material as ShaderMaterial
	# Estado inicial: botão normal, sem escurecimento algum.
	_set_reveal(1.0)


func _process(delta: float) -> void:
	if _cooldown_remaining <= 0.0:
		return
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if _cooldown_remaining <= 0.0:
		# Terminou: volta a aceitar acionamentos e o escuro some.
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


## A cobertura é a fração de tempo restante: completa quando restam
## COOLDOWN_DURATION s e proporcional a cada instante até sumir.
##
## O escuro não é um retângulo solto: é o PRÓPRIO sprite do botão
## (CooldownMask, mesma textura e mesmo ajuste de escala do botão, tingido
## de preto). Assim a silhueta arredondada em pixel art define onde o
## escuro aparece e nada vaza para fora do botão. A máscara fica fixa,
## exatamente sobre o retângulo do botão (o enquadramento da textura nunca
## muda); só o shader `reveal_frac` muda, revelando de cima para baixo a
## partir do mesmo `_cooldown_remaining` que bloqueia o botão.
func _sync_overlay() -> void:
	var ratio := clampf(_cooldown_remaining / COOLDOWN_DURATION, 0.0, 1.0)
	_set_reveal(1.0 - ratio)


## Aplica a fração já revelada no shader da máscara.
func _set_reveal(reveal_frac: float) -> void:
	if _reveal_material != null:
		_reveal_material.set_shader_parameter(REVEAL_PARAM, reveal_frac)
