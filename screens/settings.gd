extends Control
## Tela de configurações fiel ao mockup (`docs/design/settings-screen.jpg`):
## fundo de circuito, cabeçalho com "VOLTAR" + título e um painel com
## MÚSICA / EFEITOS SONOROS (sliders), INVERTER EIXO Y (toggle ON/OFF)
## e TIPO DE CONTROLE (3 opções). Todas as preferências são lidas e
## gravadas via SettingsManager (persistência automática, sem botão de
## salvar).

const PILL_BORDER := Color(0.65, 0.36, 0.94, 1)
const PILL_GREEN := Color(0.21, 0.9, 0.5, 1)
const PILL_DARK := Color(0.16, 0.08, 0.26, 1)
const PILL_TEXT_ACTIVE := Color(0.98, 1, 0.98, 1)
const PILL_TEXT_IDLE := Color(0.72, 0.5, 0.93, 1)

@onready var music_slider: VolumeSlider = $Panel/Margin/VBox/MusicSection/MusicSlider
@onready var sfx_slider: VolumeSlider = $Panel/Margin/VBox/SfxSection/SfxSlider
@onready var invert_on: Button = $Panel/Margin/VBox/InvertRow/OnButton
@onready var invert_off: Button = $Panel/Margin/VBox/InvertRow/OffButton
@onready var ctrl_buttons: Array[TextureButton] = [
	$Panel/Margin/VBox/ControlTypeSection/ControlTypeRow/CtrlType0,
	$Panel/Margin/VBox/ControlTypeSection/ControlTypeRow/CtrlType1,
	$Panel/Margin/VBox/ControlTypeSection/ControlTypeRow/CtrlType2,
]
@onready var back_button: TextureButton = $Header/Back/Home

## Metades do "pill" ON/OFF, recriadas por estado: a metade ativa fica
## verde e a inativa fica escura, mantendo a borda roxa contínua.
var _on_active: StyleBoxFlat
var _on_idle: StyleBoxFlat
var _off_active: StyleBoxFlat
var _off_idle: StyleBoxFlat


func _ready() -> void:
	_on_active = _make_pill_half(true, PILL_GREEN)
	_on_idle = _make_pill_half(true, PILL_DARK)
	_off_active = _make_pill_half(false, PILL_GREEN)
	_off_idle = _make_pill_half(false, PILL_DARK)

	music_slider.volume_changed.connect(_on_music_changed)
	sfx_slider.volume_changed.connect(_on_sfx_changed)
	invert_on.pressed.connect(_on_invert_on)
	invert_off.pressed.connect(_on_invert_off)
	back_button.pressed.connect(_on_back_pressed)

	for i in ctrl_buttons.size():
		ctrl_buttons[i].toggled.connect(_on_ctrl_type_toggled.bind(i))

	refresh()


## Contrato do ScreenNavigator: reler as preferências ao ser exibido
## (podem ter mudado via debug/testes; painel nunca é liberado).
func enter(_params: Dictionary = {}) -> void:
	if not is_node_ready():
		await ready
	refresh()


## Contrato do ScreenNavigator: nada a liberar (painel persistente).
func exit() -> void:
	pass


## Sincroniza todos os controles com o SettingsManager.
func refresh() -> void:
	if not is_node_ready():
		return
	if _on_active == null:
		return
	music_slider.set_volume(SettingsManager.get_music_volume())
	sfx_slider.set_volume(SettingsManager.get_sfx_volume())
	_update_invert_visual(SettingsManager.is_invert_y())

	var control_type := SettingsManager.get_control_type()
	for i in ctrl_buttons.size():
		ctrl_buttons[i].set_pressed_no_signal(i == control_type)


## Monta uma metade do toggle: `is_left` arredonda só o lado esquerdo
## (botão ON) ou só o direito (botão OFF), formando o pill completo.
func _make_pill_half(is_left: bool, background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = PILL_BORDER
	box.border_width_top = 2
	box.border_width_bottom = 2
	box.border_width_left = 2
	box.border_width_right = 2
	if is_left:
		box.corner_radius_top_left = 8
		box.corner_radius_bottom_left = 8
	else:
		box.corner_radius_top_right = 8
		box.corner_radius_bottom_right = 8
	return box


func _on_music_changed(value: int) -> void:
	SettingsManager.set_music_volume(value)


func _on_sfx_changed(value: int) -> void:
	SettingsManager.set_sfx_volume(value)


func _on_invert_on() -> void:
	InterfaceSoundManager.pluck()
	SettingsManager.set_invert_y(true)
	_update_invert_visual(true)


func _on_invert_off() -> void:
	InterfaceSoundManager.pluck()
	SettingsManager.set_invert_y(false)
	_update_invert_visual(false)


func _update_invert_visual(enabled: bool) -> void:
	_apply_pill_style(invert_on, _on_active if enabled else _on_idle,
			PILL_TEXT_ACTIVE if enabled else PILL_TEXT_IDLE)
	_apply_pill_style(invert_off, _off_idle if enabled else _off_active,
			PILL_TEXT_IDLE if enabled else PILL_TEXT_ACTIVE)


func _apply_pill_style(button: Button, box: StyleBoxFlat, text_color: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)


func _on_ctrl_type_toggled(pressed: bool, index: int) -> void:
	if not pressed:
		# Sempre existe uma opção marcada: reativa a que foi clicada.
		ctrl_buttons[index].set_pressed_no_signal(true)
		return
	InterfaceSoundManager.pluck()
	for i in ctrl_buttons.size():
		if i != index:
			ctrl_buttons[i].set_pressed_no_signal(false)
	SettingsManager.set_control_type(index)


func _on_back_pressed() -> void:
	InterfaceSoundManager.pluck()
	# Slide de retorno ao Home (sem rebuild, sem tocar no save).
	var nav = _navigator()
	if nav != null:
		nav.navigate_to("home")
		return
	# Fallback standalone (fora do Main): destrutivo clássico.
	get_tree().change_scene_to_file("res://screens/home.tscn")


## Navigator acima de nós (Camada própria -> ScreenHost -> Main).
## Duck-typing: qualquer nó com `navigate_to`.
func _navigator():
	var n := get_parent()
	while n != null:
		if n.has_method("navigate_to") and n.has_method("is_navigating"):
			return n
		n = n.get_parent()
	return null
