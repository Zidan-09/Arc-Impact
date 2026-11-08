extends Button

## Botão de reset do progresso — apenas para a etapa de desenvolvimento.
## Sem sprite: um `Button` com texto basta para identificar na home.
## Ao pressionar, regrava o save com a fase 1 (ver `SaveManager.reset_progress`).

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	SaveManager.reset_progress()
