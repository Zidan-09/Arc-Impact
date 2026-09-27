# Plano — Câmera estilo Angry Birds na `Game.tscn`

> Arquivo de planejamento. Nenhuma implementação foi feita aqui; este documento é a especificação
> para uma segunda execução implementar a funcionalidade.

---

## 1. Objetivo

Permitir que o jogador explore uma fase maior que a área originalmente visível (1280×720),
com um sistema de câmera inspirado em **Angry Birds** (referência conceitual de experiência,
sem copiar implementação):

- Pan horizontal e vertical para explorar regiões da fase;
- Zoom in / zoom out;
- Limites de movimento e zoom coerentes com o tamanho da fase;
- A câmera acompanha o **mundo** do jogo; o **HUD** permanece fixo;
- Retorno fácil a uma visualização adequada da fase (reset/fit);
- Preparar a arquitetura para que o **gerador procedural** possa futuramente criar fases
  maiores que a viewport sem precisar ser refeito.

Fora de escopo: mudar regras de geração, rebalancear dificuldade, reformular HUD ou
reestruturar o projeto. Alterações pequenas e coerentes com a arquitetura atual.

---

## 2. Análise da implementação atual

Levantamento feito por leitura direta dos arquivos (não assumir; verificar nos caminhos abaixo).

### 2.1. `screens/game.tscn` (o enunciado chama de `Game.tscn`; o caminho real é este)

Raiz: `Game` (`Control`, full-rect, `mouse_filter = 2` = IGNORE). Filhos:

| Nó | Tipo | Papel |
|---|---|---|
| `WorldArea` | `Control` (full-rect menos 200 px à direita, IGNORE) | Área do mundo; `offset_right = -200` reserva o painel lateral |
| `WorldArea/WorldBackground` | `TextureRect` (`background.jpg`, `expand_mode = 2`, `stretch_mode = 6`, IGNORE) | Fundo estático **em espaço de UI** — não pertence ao mundo |
| `WorldArea/World` | `Node2D` | **Mundo da fase** (contêiner em (0,0): posição local == global) |
| `WorldArea/World/Level` | `Node2D` | Contêiner onde o `LevelBuilder` instancia alvo, obstáculos, chão e projéteis |
| `WorldArea/World/Cannon` | instância `cannon.tscn`, `position = (173, 523)`, `scale = (0.2, 0.2)` | Canhão (posição sobrescrita por `game.gd` a cada fase) |
| `ControlsArea` | `Control` ancorado à direita, 200 px de largura, IGNORE | Painel lateral (fundo repetindo `background.jpg`) |
| `ControlsBackground` | `TextureRect` | Fundo do painel lateral |
| `Divider` | `ColorRect` 2 px | Divisória mundo/painel |
| `Hud` | instância `hud.tscn` (full-rect, IGNORE) | Interface (labels + controles) |
| `LevelCompletePopup` | instância `LevelCompletePopup.tscn`, `visible = false` | Popup de vitória/derrota |

**Não existe nenhum `Camera2D`** no projeto (busca por `Camera2D|camera` retorna só
`export_presets.cfg: permissions/camera=false`, que é permissão de câmera de celular,
irrelevante). Hoje a correspondência mundo↔tela é 1:1: o `Node2D` World desenha direto
no canvas, sem transformação de câmera.

### 2.2. Qual nó representa o mundo da fase

`$WorldArea/World` (`Node2D`), com filhos `Level` (conteúdo gerado) e `Cannon`.
Referências em `screens/game.gd:6-9`:

```gdscript
@onready var world_area: Control = $WorldArea
@onready var world: Node2D = $WorldArea/World
@onready var level_node: Node2D = $WorldArea/World/Level
@onready var cannon: Cannon = $WorldArea/World/Cannon
```

Tudo que deve sofrer pan/zoom precisa estar sob `World`. Tudo que deve ficar fixo
precisa estar **fora** de `World` (irmão da raiz, como `Hud` já está).

### 2.3. HUD e interface

`components/hud/hud.tscn`: raiz `Hud` (`Control` full-rect, IGNORE), filhos:

- `Info/MarginContainer` → `VBoxContainer/Column` → `Level`, `Score`, `Ammo` (`Label`s,
  canto superior esquerdo, IGNORE — não interceptam clique);
- `Controls` (`Control` ancorado inferior-direito, `offset_left = -200`, IGNORE) →
  `PowerSlider` (instância `powerSlider.tscn`, raiz IGNORE, `Track`/`Handle` com
  `mouse_filter = 0` = STOP) e `FireButton` (instância `fireButton.tscn`).

`components/hud/hud.gd`: só `set_ammo()` e `set_level()`. Não faz conversão de
coordenadas; **não deve ser alterado** para a câmera.

`ControlsArea` (painel de 200 px em `game.tscn`) × `Hud/Controls` (controles funcionais)
são nós distintos que ocupam a mesma faixa direita. O `WorldArea` já exclui esses
200 px (`offset_right = -200`).

### 2.4. Como a fase é gerada hoje (`screens/game.gd:45-75`)

1. `FastLevelGenerator.generate(seed, level_number)` — síncrono, determinístico,
   só matemática/geometria (solução analítica + `LevelValidator`), sem física;
2. `await builder.build(level_node, def)` — `LevelBuilder` instancia os Nodes em `Level`;
3. `cannon.position = def.cannon_position`;
4. `ammo_total/left = def.ammo`; conecta `target.hit`; atualiza o HUD.

`CannonController.tscn` + `cannon_controller.gd` é um fluxo legado/standalone
equivalente (usa `ProceduralLevelGenerator` com física); o fluxo canônico do jogo é
`screens/game.tscn` + `screens/game.gd`. **A câmera entra só no fluxo canônico.**

### 2.5. Dimensões e limites atuais da fase

| Fonte | Valor | Significado |
|---|---|---|
| `level_definition.gd:19` | `play_bounds = Rect2(0, 0, 1280, 720)` | Retângulo jogável = exatamente a viewport base |
| `level_definition.gd:13` | `cannon_position = Vector2(173, 523)` | Fixo na v1 |
| `level_archetype.gd:29` | `spot_target() = (950..1200, 80..640)` | Alvo sempre no terço direito, dentro da tela |
| `level_validator.gd` | `MIN_CANNON_TARGET_DIST = 500`, `CANNON_EXCLUSION = 150`, `TARGET_EXCLUSION = 100`, tudo precisa estar `encloses` em `play_bounds` | Toda a fase cabe na tela por construção |
| `level_builder.gd:12-15` | `GROUND_Y = 670`, `GROUND_FROM_X = 50`, `GROUND_TO_X = 1250`, passo 100 | Chão fixo cobrindo 50..1250 |
| `fast_level_generator.gd:21-22` | `GROUND_TOP = 620`, `TARGET_MAX_Y = 575`, `KILL_MARGIN = 400` | Teto do chão; `kill_rect = play_bounds.grow(400)` |
| `project.godot:21-24` | viewport `1280×720`, `stretch = canvas_items`, `aspect = expand` | Tamanho base; em telas maiores o canvas expande |

Conclusão: hoje **mundo = área visível = viewport**. A câmera precisa quebrar essa
igualdade em três conceitos distintos: `world_bounds` (tamanho da fase) × área visível
(função de zoom + viewport) × viewport (janela).

### 2.6. Posicionamento de canhão, alvo, obstáculos, terreno

- Canhão: `cannon_position` do `LevelDefinition` (fixo 173,523 na v1), aplicado em
  `game.gd:66`. O `muzzle_state_for()` (`cannon.gd:79-84`) é matemática pura usada
  pelos geradores — não depende de câmera.
- Alvo: `TargetDefinition.position` (padrão 1000,360; ultimate 1000,326), cena
  `target.tscn` = `Area2D` 80×80 com mira desenhada por `_draw`.
- Obstáculos: `ObstacleDefinition` (kind/position/rotation/scale), instanciados via
  `MaterialRules.scene_for()`; AABB ≈ `base_size * scale` (vidro 952×934, pedra 500×500,
  metal 548×548, escala típica 0.1–0.2).
- Terreno: `floor.tscn` = `StaticBody2D` com `RectangleShape2D` 500×500 (escala 0.2 →
  ~100 px efetivos), enfileirado pelo `LevelBuilder.build_ground()`.
- Projétil: `bullet.gd` (`RigidBody2D`); `apply_cannon_scale()` ajusta raios sem tocar
  em massa/velocidade. Física e colisões vivem no espaço do mundo — **câmera (transform
  de canvas) não afeta física nem colisão**.

### 2.7. Câmera existente

Nenhuma. Nem `Camera2D`, nem `ParallaxBackground`, nem ações de input de zoom/pan.
`project.godot` não tem seção `[input]` — todo input é tratado por eventos crus em
`game.gd` (`_input`/`_unhandled_input`) e `power_slider.gd` (`gui_input`/`_input`).

### 2.8. Como cenas/scripts serão afetados

- `screens/game.tscn`: recebe o nó `Camera2D` (única mudança estrutural necessária).
- `screens/game.gd`: configura a câmera, informa os limites a cada `load_level()`,
  roteia input de pan/zoom sem quebrar a mira. É o arquivo mais afetado.
- `WorldBackground` (`TextureRect` em espaço de UI): **é o maior problema escondido**.
  Por ser `Control`, ele ignora `Camera2D`. Com pan/zoom, o mundo se move mas o fundo
  fica parado (canhão/obstáculos flutuando sobre imagem fixa). Precisa de tratamento
  (§9, §12).
- `hud.tscn`/`hud.gd`, `cannon.gd`, `bullet.gd`, `target.gd`, `trajectory_line.gd`,
  validador, solver, geradores: **não precisam de mudança funcional** (§11 explica por quê).

### 2.9. Elementos que NÃO devem sofrer zoom/pan

`Hud` (labels, `PowerSlider`, `FireButton`), `ControlsArea` + `ControlsBackground`,
`Divider`, `LevelCompletePopup`. Todos já são irmãos da raiz, fora de `World` —
a separação existe, basta não movê-los para dentro de `World`.

### 2.10. Coordenadas/limites fixos que amarram o mapa ao tamanho da tela

1. `LevelDefinition.play_bounds = Rect2(0, 0, 1280, 720)` — trava geração, validação,
   `kill_rect` e solver no tamanho da viewport;
2. `spot_target()` — faixa x 950..1200 pressupõe largura 1280;
3. `LevelBuilder.GROUND_FROM_X/TO_X` (50..1250) — chão pressupõe largura 1280;
4. `game.gd:_press_in_world()` — usa `world_area.get_global_transform_with_canvas()`,
   correto sem câmera e continua válido com câmera para o teste de "está dentro do
   `WorldArea`", mas qualquer futura conversão mundo↔tela deve usar a câmera
   (`get_global_mouse_position()` passa a ser câmera-dependente automaticamente);
5. Mira atual usa `event.relative` (pixels de tela, eixo Y) — funciona com câmera sem
   conversão, mas a sensibilidade percebida muda com o zoom (ver §11).

---

## 3. Arquitetura proposta

Solução idiomática Godot 4: um `Camera2D` com script próprio, filho de `World`.

```
Game (Control, raiz — inalterado)
├── WorldArea (Control — inalterado)
│   ├── WorldBackground (TextureRect — ver §9: manter como pano de fundo fixo
│   │                     + adicionar backdrop em espaço de mundo, ou migrar)
│   └── World (Node2D — inalterado, passa a ser observado pela câmera)
│       ├── Level (Node2D — inalterado; conteúdo gerado)
│       ├── Cannon (inalterado)
│       └── GameCamera (Camera2D, NOVO — script game_camera.gd, enabled)
├── ControlsArea, Divider, Hud, LevelCompletePopup (inalterados, fora da câmera)
```

Princípios:

1. **Só `World` é afetado pela câmera.** Nenhum nó de UI entra em `World`; nenhum nó
   de mundo sai dele.
2. **Câmera burra sobre jogo, jogo burro sobre câmera.** A câmera expõe
   `set_bounds(Rect2)`, `reset_view()`, `fit_to_bounds()` e sinais de estado;
   `game.gd` a alimenta com os limites da fase em `load_level()` e nada mais.
3. **Limites dinâmicos, não constantes.** A câmera nunca hard-coda 1280×720; recebe um
   `Rect2` por fase (§8). Hoje ele vale `(0,0,1280,720)`; quando o gerador crescer,
   o mesmo caminho entrega `(0,0,2560,1440)` sem mudar a câmera.
4. **Sem `InputMap` novo por padrão.** O projeto não tem seção `[input]` e trata tudo
   por eventos crus; pan/zoom seguem o mesmo estilo (`_unhandled_input` com
   `InputEventMouseButton/MouseMotion/ScreenTouch/ScreenDrag`), evitando difusão de
   configuração. Teclas de apoio (setas/WASD, `R`, `+`/`-`) são lidas por `Input.is_key_pressed`
   ou `InputEventKey` no mesmo handler.
5. **Física e solução imutáveis.** Validador, solver, `kill_rect`, `muzzle_state_for()`
   e `LevelBuilder` operam em coordenadas de mundo; câmera é só transformação de
   visualização (`canvas_transform`). Nenhum deles recebe referência à câmera.

Novo conceito de dados (única extensão de dados necessária agora):

- `LevelDefinition.world_bounds: Rect2` (padrão = `Rect2(0, 0, 1280, 720)`), serializado
  em `to_dict()`/`from_dict()` ao lado de `play_bounds`. Na v1 ele **espelha**
  `play_bounds`; no futuro o gerador o amplia e a câmera o consome. `play_bounds`
  mantém seu significado atual (regras/validação/kill) para não invalidar o pipeline.

---

## 4. Estrutura da `Game.tscn` após a alteração

Caminho real do arquivo: **`screens/game.tscn`** (o nome `Game` é o nó raiz).

```ini
[node name="GameCamera" type="Camera2D" parent="WorldArea/World"]
position = Vector2(640, 360)
zoom = Vector2(1, 1)
position_smoothing_enabled = false
editor_draw_limits = true
script = ExtResource("game_camera_script")  ; res://components/camera/game_camera.gd
```

- Único nó adicionado. `CannonController.tscn` (fluxo legado) **não** é alterado.
- `position` inicial = centro dos limites da fase (640,360 para a fase atual);
  `game.gd` recalcula via `reset_view()` a cada `load_level()`.
- `enabled = true` (em Godot 4.x `Camera2D.enabled`, default true quando é a primeira
  câmera que entra na árvore; setar explicitamente no `.tscn` e/ou `_ready()`).
- `position_smoothing_enabled = false` por padrão: pan por arrasto deve ser 1:1;
  o zoom usa suavização própria no script (lerp), não o smoothing de posição
  (que atrasaria o pan e conflitaria com o clamp).
- `editor_draw_limits = true` ajuda a visualizar no editor; os limites reais são
  aplicados por código via `set_bounds()`, não pelas propriedades `limit_*`
  (ver §8 — clamp manual é mais previsível com zoom variável e `aspect = expand`).
- Nenhum outro nó muda de pai, de ordem ou de `mouse_filter`. Em particular:
  `Hud`, `ControlsArea`, `Divider` e `Popup` continuam irmãos da raiz.

Dependência: o `ExtResource` do script exige que `components/camera/game_camera.gd`
exista antes (etapa 1 cria o script, etapa 2 edita a cena).

---

## 5. Comportamento da `Camera2D`

Script novo `components/camera/game_camera.gd` (`class_name GameCamera extends Camera2D`):

| Propriedade | Valor padrão | Justificativa |
|---|---|---|
| `zoom` inicial | `(1, 1)` | Comportamento atual preservado; fase 1280×720 ocupa a tela como hoje |
| `zoom_min` | `0.5` | Com 1280×720 de viewport, mostra 2560×1440 — cobre a fase atual inteira com folga e antecipa fases 2× maiores sem pixelar o fundo além do razoável |
| `zoom_max` | `2.0` | Mostra 640×360 — detalhe da região do canhão/alvo; acima disso os sprites (fundo 1280 px, obstáculos ~100 px) degradam e a mira perde contexto |
| passo de zoom (roda) | `×1.1` por tick (≈ `zoom *= 1.1` / `/= 1.1`) | Padrão de mercado; ~7 ticks de 0.5→1.0, granularidade boa semassar o usuário |
| suavização de zoom | lerp exponencial `zoom.lerp(alvo, 1 - exp(-10 * delta))` em `_process()` | Transição suave sem atraso perceptível; pan continua instantâneo |
| `position` | centro dos limites | Fase atual: (640, 360) = exatamente o enquadramento de hoje |

Comportamentos:

- `set_bounds(bounds: Rect2)`: armazena limites, chama `reset_view()`.
- `reset_view()`: `zoom = (1,1)` (ou `fit` se a fase for maior que a viewport — ver §10),
  `position` = ponto de interesse inicial (centro entre canhão e alvo quando ambos
  conhecidos; senão centro dos limites). Chamado em todo `load_level()`.
- `fit_to_bounds()`: calcula `zoom = min(viewport/bounds.size)` para exibir a fase
  inteira; usado pelo reset quando a fase exceder a viewport e por botão dedicado.
- Clamp executado em `set_bounds()`, após cada pan/zoom e em `NOTIFICATION`/`resized`
  do viewport (necessário por `aspect = expand`: a área visível muda com a janela).
- A câmera **nunca** altera física, colisões, `play_bounds`, geração ou HUD — só
  `position` e `zoom` próprios.

Referência espacial (§7.6): além do clamp, o reset é sempre acessível (tecla `R`,
botão "Centralizar" no HUD — adição futura mínima — e duplo-clique com botão direito),
e o fundo do mundo (§9) dá contexto contínuo durante o pan.

---

## 6. Pan da câmera

### 6.1. O conflito central

Hoje **qualquer arrasto com botão esquerdo dentro do `WorldArea` mira o canhão**
(`game.gd:139-150`: press → `_dragging_angle = true`; motion vertical →
`rotate_cannon(-relative.y)`). Reutilizar o mesmo gesto para pan quebraria a mira.
A decisão abaixo preserva 100% do gameplay atual.

### 6.2. Mapeamento proposto (PC + mobile)

| Dispositivo | Gesto de pan | Por quê |
|---|---|---|
| Mouse | **Arrastar com botão direito OU botão do meio** | Botão esquerdo fica exclusivo da mira; direito/meio não têm uso atual no jogo |
| Mouse (alternativo) | Setas / WASD (pan contínuo ~600 px/s ÷ zoom) | Acessibilidade, precisão fina |
| Touch | **Arrasto com 2 dedos** (`InputEventScreenDrag` com `index > 0` ativo) | 1 dedo continua mirando, como hoje; pinça (2 dedos) faz zoom (§7) |
| Todos | Tecla `R` / botão HUD futuro / duplo-clique botão direito → `reset_view()` | Volta à referência (§5) |

Comportamento durante o arrasto:

- Pan 1:1 em espaço de mundo: `camera.position -= event.relative / camera.zoom.x`
  (para `MouseMotion` com o botão pressionado) ou `-event.relative / zoom` para
  `ScreenDrag`. Dividir pelo zoom mantém a sensação "agarrar o mundo" em qualquer zoom.
- Clamp a cada motion (§8); sem inércia na v1 (simplicidade; Angry Birds tem leve
  deslize, mas inércia exige tuning e pode empurrar a câmera para fora dos limites —
  registrar como melhoria futura, não v1).
- Cursor: mudar para "mão fechada" durante o pan (cosmético, opcional na v1).

### 6.3. Roteamento de input (evitar conflito com a mira)

Ordem de consumo (Godot: `gui_input` → `_unhandled_input`):

1. `PowerSlider`/`FireButton` consomem via `gui_input` + `set_input_as_handled()` —
   cliques neles **nunca** chegam ao pan/mira (já funciona hoje, manter).
2. Em `game.gd._unhandled_input()`:
   - `MOUSE_BUTTON_RIGHT/MIDDLE` press/release → inicia/termina pan; `MouseMotion`
     com pan ativo → move câmera; **chamar `get_viewport().set_input_as_handled()`**
     para não iniciar mira;
   - `MOUSE_BUTTON_LEFT` → comportamento atual **inalterado** (mira);
   - Roda (`WHEEL_UP/DOWN/BUTTON`) → zoom (§7), nunca mira;
   - `ScreenTouch index == 0` sozinho → mira (inalterado); segundo dedo
     (`index == 1` press) → cancela `_dragging_angle` e inicia pan/pinça; soltura
     total → encerra.
3. Regra de ouro: **pan e mira nunca ativos simultaneamente** — iniciar um cancela o
   outro (`_dragging_angle = false` ao iniciar pan e vice-versa).

### 6.4. Interação com o gameplay

- Mirar continua funcionando com a câmera em qualquer posição/zoom (usa
  `event.relative.y`, pixels de tela — ver ressalva de sensibilidade em §11).
- Disparo, projétil, obstáculos e terreno não recebem input de câmera; só `game.gd`
  e `game_camera.gd` tratam esses eventos.

---

## 7. Sistema de zoom

| Aspecto | Definição | Justificativa |
|---|---|---|
| Zoom mínimo | `0.5` | Fase atual (1280×720) cabe com margem; fase futura de até ~2560×1440 ainda é enquadrável inteira |
| Zoom máximo | `2.0` | Detalhe sem degradar sprites nem perder contexto tático; trajetória (`max_distance = 400` px de mundo) continua legível |
| Sensibilidade (roda) | fator `1.1` por tick, clamp em `[0.5, 2.0]` | ~24 ticks cobrem toda a faixa; nem lento nem brusco |
| Sensibilidade (teclado) | `+`/`-` ou `=`/`-` ajustam `±0.1`, contínuo se segurado | Acessível sem mouse |
| Sensibilidade (pinça) | `zoom *= dist_novo/dist_anterior` (relativo, sem constante) | Segue o gesto do usuário; clamp idem |
| Entrada | Roda do mouse, pinça de 2 dedos, teclas `+`/`-` | Cobre desktop + mobile (alvo do projeto: Android/iOS + PC/Web) |
| Ponto focal | **Posição do cursor** (mouse) / ponto médio da pinça (touch) | Padrão Angry Birds/Google Maps: o ponto sob o cursor permanece sob o cursor; muito superior ao zoom-no-centro para exploração |
| Anti-perda de referência | Clamp pós-zoom (§8) + `R`/reset sempre disponível + zoom nunca abaixo do `fit` da fase atual | Impossível "se perder no vazio": ao reduzir além do necessário, a câmera recentraliza |

### Implementação do zoom-no-cursor (único ponto matematicamente delicado)

Antes de alterar o zoom, capturar `mundo_antes = get_global_mouse_position()`;
aplicar o novo zoom (com clamp); reposicionar:
`position += mundo_antes - get_global_mouse_position()`. Na pinça, usar o ponto
médio dos dois toques como âncora (aproximação: cursor ou centro da tela se o ponto
médio não estiver disponível no frame). Reaplicar o clamp de limites em seguida —
a ordem é **zoom → âncora → clamp**, nunca o inverso (clamp antes da âncora
deslocaria o ponto focal).

### Por que não zoom-no-centro

Zoom-no-centro empurra o ponto de interesse para fora da tela a cada tick quando o
usuário olha as bordas (justamente onde estarão canhão/alvo em fases grandes).
O custo do zoom-no-cursor são 3 linhas (captura/âncora) e está isolado em
`game_camera.gd`, sem tocar em gameplay.

---

## 8. Limites dinâmicos da câmera

### 8.1. Fonte da verdade

`LevelDefinition.world_bounds: Rect2` (novo, §3; padrão `Rect2(0, 0, 1280, 720)`).
Fluxo: gerador preenche → `game.gd load_level()` passa para
`game_camera.set_bounds(def.world_bounds)` (com fallback para `play_bounds` se
`world_bounds` for nulo/vazio — robustez para defs serializadas antigas via
`from_dict()`).

### 8.2. Cálculo do clamp (executado após pan, zoom, resize e `set_bounds`)

```
half_view = viewport_size / 2 / zoom   # viewport_size = get_viewport_rect().size
if bounds.size.x <= half_view.x * 2: center.x = bounds.get_center().x
else: center.x = clamp(center.x, bounds.position.x + half_view.x - MARGIN,
                                   bounds.end.x - half_view.x + MARGIN)
(idem Y)
```

- `MARGIN ≈ 100 px` de mundo: permite ver um respiro além da borda (contexto visual)
  sem navegar "indefinidamente para fora da área da fase".
- Se a visão for maior que a fase (zoom 0.5 em fase 1280×720), centraliza em vez de
  clampar — evita trava assimétrica num canto.
- Usar `get_viewport_rect().size` (não constante 1280×720) por causa de
  `aspect = expand`: em 19.5:9 ou 16:10 a área visível real difere da base.
- **Não usar `Camera2D.limit_*`** para isso: os limites nativos não recentralizam
  quando a visão excede os limites e interagem mal com zoom animado; o clamp manual
  de 10 linhas é determinístico e testável sem rodar o editor.

### 8.3. Terreno e limites

Na v1 o chão (`build_ground`, 50..1250) já está contido nos limites padrão. Quando o
gerador ampliar `world_bounds`, o `LevelBuilder` deverá estender o chão
(`GROUND_FROM_X/TO_X` derivados de `world_bounds`, não constantes) — registrado como
etapa futura em §13, sem mudar geração agora.

---

## 9. Separação entre mundo e HUD

| Camada | Nós | Efeito da câmera |
|---|---|---|
| **Mundo** (sob `WorldArea/World`) | `Level` (alvo, obstáculos, chão, projéteis), `Cannon` (+ `TrajectoryLine`), `GameCamera`, backdrop de mundo (novo, abaixo) | Pan/zoom aplicam-se integralmente |
| **Interface** (irmãos da raiz) | `Hud` + `ControlsArea` + `Divider` + `LevelCompletePopup` | **Zero efeito**: `Control`s fora de `World` ignoram `Camera2D` por construção |

Garantias:

1. Nenhum `Control` entra em `World`; nenhum `Node2D` de jogo sai dele.
2. O script da câmera nunca referencia `$Hud`, slider, botão ou popup (e vice-versa).
3. `TrajectoryLine` é filha do canhão (mundo) — dá zoom junto, **correto**: a prévia
   representa metros de mundo, não pixels de tela.

### O caso `WorldBackground` (decisão obrigatória na implementação)

O `TextureRect` atual é UI e **não acompanha a câmera**. Opções (escolher uma na
implementação; recomendada: **A**):

- **A (recomendada):** adicionar um backdrop em espaço de mundo — `Sprite2D`
  (mesma `background.jpg`, centrado em `world_bounds.get_center()`, escalado para
  cobrir `bounds.size + margem`) como **primeiro filho de `World`** (z atrás), e
  manter o `TextureRect` atual como cor/moldura de letterbox. Mudança mínima, resolve
  o "mundo flutuando sobre fundo parado".
- **B:** migrar o fundo para `ParallaxBackground` com scroll que siga a câmera.
  Mais fiel a Angry Birds, porém mais arquivos e tuning; deixar para refinamento.
- **C (rejeitada):** manter só o `TextureRect` — com qualquer pan o fundo descola do
  mundo; inaceitável após zoom 1:1 deixar de valer.

Critério: com zoom 0.5 e pan até os limites, nenhum pixel de mundo pode ficar sobre
"vazio de editor" — o backdrop de mundo deve cobrir `world_bounds + MARGIN` em
qualquer zoom permitido.

---

## 10. Integração com o gerador de fases

**Nada da geração muda nesta entrega** — só os pontos de integração:

1. **Novo campo `LevelDefinition.world_bounds`** (padrão = `play_bounds`), com
   `to_dict()`/`from_dict()` estendidos. É o contrato futuro: quando os arquétipos
   gerarem em áreas maiores, preenchem `world_bounds` com a área real e a câmera
   obedece sem alteração.
2. **`game.gd load_level()`**: após `builder.build()`, chamar
   `game_camera.set_bounds(current_def.world_bounds)` e
   `game_camera.reset_view(cannon.position, target.position)`. Posição inicial =
   **ponto médio canhão↔alvo com zoom fit se a distância exceder a viewport** —
   assim, se o objetivo estiver fora da área inicialmente visível (caso futuro
   central da feature), o jogador o descobre no enquadramento inicial ou com um
   pan curto, nunca perdido.
3. **Invariantes que o gerador futuro deve manter** (documentar, não implementar):
   `world_bounds.encloses(play_bounds)`; canhão e alvo dentro de `world_bounds`;
   `spot_target()` e `rand_point()` sorteiam dentro de `world_bounds` (parametrizar
   pelos limites em vez das constantes 950..1200/80..640); `build_ground()` cobre
   `world_bounds`; `kill_rect` continua derivado de `play_bounds` (lógica), não de
   `world_bounds` (visual).
4. **Validador/solver intocados**: validam `play_bounds` (regras do jogo). A câmera
   lê `world_bounds` (apresentação). As duas caixas coincidem na v1 por construção
   (`world_bounds := play_bounds` no `_skeleton()` dos dois geradores), então nenhum
   teste existente quebra.

Exploração futura habilitada (sem implementar agora): alvo fora da visão inicial,
áreas que exigem pan para serem encontradas, fases 2–4× a viewport.

---

## 11. Impactos no gameplay/input

| Sistema | Efeito da câmera | Ação |
|---|---|---|
| Mira (`rotate_cannon(-relative.y)`) | `event.relative` é delta de tela: a mira **continua funcionando** em qualquer pan/zoom, mas a sensibilidade *percebida* varia com o zoom (mesmo gesto cobre menos mundo com zoom in) | Aceitar na v1 (comportamento previsível, sem conversão errada); registrar normalização por zoom (`relative / zoom`) como ajuste futuro **só** se playtest indicar |
| `_press_in_world()` | Teste de "clique dentro do `WorldArea`" via `get_global_transform_with_canvas()` continua válido (é teste de UI, não de mundo) | Manter; **não** converter para coords de mundo — a mira não precisa delas |
| Disparo / projétil / física | `RigidBody2D`, `Area2D`, `StaticBody2D` vivem em espaço de mundo; câmera é `canvas_transform` | **Nenhum impacto**; colisões idênticas com ou sem câmera |
| `TrajectoryLine` | Filha do canhão; `update_trajectory()` calcula em coords globais de mundo e converte com `to_local()` | Zoom correto por construção; `max_distance = 400` são px de mundo (encolhe na tela com zoom out — correto, é distância real) |
| `BulletReturnDetector` | `Area2D` filha do canhão | Sem impacto |
| `PowerSlider` / `FireButton` | Consomem `gui_input` antes de `_unhandled_input` | Pan/zoom nunca disparam ao usar controles (manter `set_input_as_handled()`) |
| Pan com botão direito | Sem uso atual; menu de contexto não existe em jogo Godot | Seguro |
| `Cannon.scale = 0.2` + `apply_cannon_scale()` | Geometria de mundo | Sem impacto (câmera não toca em escala de nó) |
| `aspect = expand` + telas variadas | Área visível real ≠ 1280×720 | Clamp usa `get_viewport_rect().size` real (§8); testar em 16:9, 19.5:9 e 16:10 (RNF-002 do PRD) |
| `SimulationWorld` / solver | Sandbox invisível sem câmera | Não instanciar nem referenciar `GameCamera` lá |

---

## 12. Arquivos que precisarão ser criados ou modificados

### NOVO — `components/camera/game_camera.gd`

- Responsabilidade atual: não existe.
- Alteração: criar `class_name GameCamera extends Camera2D` com `zoom_min/max`,
  alvo de zoom + suavização, `set_bounds()`, `reset_view()`, `fit_to_bounds()`,
  clamp manual, zoom-no-cursor, pan por delta (`pan_by(screen_delta)`).
- Motivo: isolar 100% da lógica de câmera num componente testável; `game.gd` só
  roteia eventos e informa limites.
- Dependências: nenhuma (só API Godot `Camera2D`); `screens/game.tscn` referencia este
  script (criar antes de editar a cena).

### MODIFICAR — `screens/game.tscn`

- Responsabilidade atual: layout `Game` sem câmera (§2.1).
- Alteração: adicionar nó `GameCamera` (`Camera2D` + script) como filho de
  `WorldArea/World` (§4) + `ExtResource` do script. Opcional nesta entrega: backdrop
  de mundo (§9, opção A) como primeiro filho de `World`.
- Motivo: introduzir a câmera sem mover nenhum nó existente.
- Dependências: exige `game_camera.gd` criado; `game.gd` precisa do `@onready` novo.

### MODIFICAR — `screens/game.gd`

- Responsabilidade atual: gerar fase, munição, disparo, mira por arrasto esquerdo,
  HUD, popups (§2.4).
- Alteração:
  1. `@onready var game_camera: GameCamera = $WorldArea/World/GameCamera`;
  2. em `load_level()`, após `builder.build()`: `set_bounds(def.world_bounds)` +
     `reset_view(cannon/target)`; habilitar câmera (`make_current()`/`enabled = true`);
  3. `_unhandled_input()`: pan (botão direito/meio, 2 dedos, setas/WASD), zoom
     (roda, pinça, `+`/`-`), `R` = reset; exclusão mútua pan↔mira; `set_input_as_handled()`
     no que consumir;
  4. `_input()`: encerrar pan na soltura (espelho do `_dragging_angle` existente);
  5. (Opcional v1) `_notification(NOTIFICATION_WM_SIZE_CHANGED)` → `game_camera.refresh()`.
- Motivo: conectar câmera ao ciclo de vida da fase e ao input sem duplicar lógica.
- Dependências: `game_camera.gd` + `world_bounds` + nó da cena.

### MODIFICAR — `components/level/level_definition.gd`

- Responsabilidade atual: dados puros da fase (`play_bounds`, canhão, alvo, obstáculos).
- Alteração: adicionar `@export var world_bounds: Rect2` (padrão `Rect2(0, 0, 1280, 720)`),
  estender `to_dict()`/`from_dict()` (fallback para `play_bounds` quando ausente —
  compatibilidade com saves/dicts antigos).
- Motivo: contrato de limites câmera↔gerador (§8, §10) sem mudar `play_bounds`.
- Dependências: nenhuma; mas `game.gd` e `_skeleton()` dos geradores a consomem.

### MODIFICAR (mínimo) — `components/level/fast_level_generator.gd` e `procedural_level_generator.gd`

- Responsabilidade atual: `_skeleton()` cria `LevelDefinition` com defaults.
- Alteração: em `_skeleton()`/`skeleton()`, setar explicitamente
  `def.world_bounds = def.play_bounds` (1 linha cada).
- Motivo: tornar o contrato explícito para o gerador futuro; zero mudança de comportamento.
- Dependências: campo `world_bounds` existir.

### NÃO TOCAR

- `components/hud/*`, `cannon.gd`, `bullet.gd`, `target.gd`, `trajectory_line.gd`,
  `level_validator.gd`, `level_solver.gd`, `simulation_world.gd`, `level_builder.gd`
  (chão), `CannonController.tscn`, `project.godot` (sem `[input]` novo — eventos crus).
  Motivo: separação mundo×HUD e física ficam intactas;_BUILDER chão só muda quando o
  gerador crescer (§8.3).

---

## 13. Sequência de implementação em etapas

| # | Etapa | Arquivos | Verificação |
|---|---|---|---|
| 0 | Preparação: rodar o jogo (`screens/game.tscn`), confirmar fase 1280×720 sem câmera; anotar posição do canhão/alvo | — | Baseline visual |
| 1 | Criar `components/camera/game_camera.gd`: `set_bounds`, clamp (§8), `reset_view`, `fit_to_bounds`, zoom clampado com suavização, `pan_by()` | 1 novo | Script carrega sem erros (sem cena ainda) |
| 2 | Adicionar `GameCamera` em `screens/game.tscn` + `@onready` em `game.gd`; hardship: `enabled`, posição inicial (640,360) | cena + `game.gd` | Jogo abre idêntico a antes (zoom 1, sem regressão) |
| 3 | Ligar limites: `world_bounds` em `level_definition.gd` (+ dict), `_skeleton()` nos 2 geradores, `set_bounds()` em `load_level()` | 3 arquivos | Trocar de fase recentraliza; nada visual muda ainda |
| 4 | Pan: botão direito/meio + WASD/setas + 2 dedos; exclusão mútua com mira; clamp por motion | `game.gd` + `game_camera.gd` | Arrastar explora a fase; mira esquerda intacta; impossível sair dos limites+`MARGIN` |
| 5 | Zoom: roda (×1.1), `+`/`-`, pinça; zoom-no-cursor (§7); clamp pós-zoom; suavização | `game.gd` + `game_camera.gd` | Cursor ancora o zoom; faixa [0.5, 2.0] respeitada |
| 6 | Reset: `R` + `reset_view()` em todo `load_level()` (+ duplo-clique direito, opcional) | `game.gd` | Um toque volta ao enquadramento canhão↔alvo |
| 7 | Backdrop de mundo (§9, opção A) cobrindo `bounds + MARGIN` | `screens/game.tscn` | Pan/zoom até os limites nunca mostra vazio |
| 8 | Prova de fase maior: teste temporário com `world_bounds = Rect2(0,0,2560,1440)` (só para validar clamp/fit/zoom — **reverter**; não é regra de geração nova) | temporário | Fit mostra tudo; pan cobre tudo; HUD fixo; física normal |
| 9 | Validação final: 16:9 + 19.5:9 + resize; touch (1 dedo mira, 2 dedos pan/pinça); `R`; trocar seed/fase sem estado vazado | — | Critérios de aceitação (§14) todos verdes |

Dependências: 1→2→3→(4,5 em qualquer ordem)→6→7→8→9. Nada de 4–8 funciona sem 1–3.

---

## 14. Critérios de aceitação

- [ ] Jogador aumenta e reduz o zoom (roda, `+`/`-`, pinça) dentro de [0.5, 2.0], com
  zoom ancorado no cursor/pinça e transição suave;
- [ ] Jogador move a câmera por toda a fase (botão direito/meio, WASD/setas, 2 dedos),
  sensação 1:1 ("agarrar o mundo");
- [ ] A câmera possui limites: impossível navegar para áreas absurdamente distantes
  (clamp em `world_bounds + MARGIN ≈ 100 px`; visão maior que a fase centraliza);
- [ ] Os limites acompanham o tamanho da fase (`set_bounds()` por `load_level()`,
  via `world_bounds`; fallback para `play_bounds` em defs antigas);
- [ ] HUD (`Hud`, `ControlsArea`, `Divider`, popup) permanece fixo — zero pan/zoom/resize;
- [ ] Colisões e física inalteradas (mesma fase, mesma seed → mesmo comportamento de
  tiro, com qualquer posição/zoom de câmera);
- [ ] Sistema funciona com fases maiores que a viewport (prova temporária 2560×1440
  da etapa 8: fit + pan total + zoom);
- [ ] Gerador pode usar área maior no futuro preenchendo só `world_bounds` (+ pontos
  de §10), sem refazer pipeline, validador ou solver;
- [ ] Experiência geral de exploração equivalente a Angry Birds: ver a fase inteira,
  aproximar região de interesse, nunca se perder (clamp + reset imediato);
- [ ] Implementação simples: 1 script novo + 1 nó + edições pontuais em `game.gd`,
  `level_definition.gd` e `_skeleton()`; nenhum arquivo de gameplay reescrito.

---

## 15. Riscos e possíveis problemas

| # | Risco | Probabilidade / Impacto | Mitigação |
|---|---|---|---|
| 1 | `WorldBackground` (UI) descola do mundo no primeiro pan — o defeito visual mais provável | Alta / Alto | Etapa 7 obrigatória (§9, opção A); nunca declarar "pronto" sem ela |
| 2 | Conflito pan×mira (regressão do controle principal) | Média / Alto | Botão esquerdo exclusivo da mira; exclusão mútua explícita; testes de mira em todo zoom (§6.3) |
| 3 | Zoom-no-cursor com ordem errada (clamp antes da âncora) desloca o foco | Média / Médio | Ordem fixa zoom→âncora→clamp (§7); revisar as 3 linhas |
| 4 | `aspect = expand` + telas exóticas quebram o clamp hard-codado | Média / Médio | Clamp usa `get_viewport_rect().size` real + `refresh()` em resize; testar 3 aspects (etapa 9) |
| 5 | Pinça de 2 dedos cancela a mira no meio do gesto / estados presos (`_dragging_angle` / pan presos após soltura fora) | Média / Médio | Cancelamento explícito ao 2º toque; encerramento em qualquer soltura (espelho do padrão `power_slider.gd`); `set_input_as_handled()` |
| 6 | Sensibilidade da mira parece mudar com o zoom (delta de tela × mundo variável) | Baixa / Baixo | Aceitar na v1; normalizar por zoom só com evidência de playtest (§11) |
| 7 | Futura fase maior exige chão, `spot_target()` e validador além de 1280 — alguém tenta "aproveitar" e muda geração junto | Baixa / Alto | Proibido nesta entrega (§10); só `world_bounds = play_bounds` + prova temporária revertida |
| 8 | Confundir `screens/game.tscn` com `CannonController.tscn` e aplicar a câmera no fluxo legado | Baixa / Médio | Alterar **só** `screens/game.tscn`; `CannonController` herda o padrão depois |
| 9 | Usar `Camera2D.limit_*` em vez do clamp manual e travar a câmera em cantos com zoom out | Baixa / Médio | Decisão registrada em §8.2; não usar `limit_*` para limites de fase |
| 10 | Backdrop de mundo em resolução insuficiente com zoom 2.0 | Baixa / Baixo | `background.jpg` cobre 1280 px de mundo; zoom in mostra sub-região (sem perda nova); zoom out min 0.5 define o requisito de cobertura, não de nitidez |

---

*Revisão de dependências (check final): `game_camera.gd` precede a cena; a cena precede
o `@onready`; `world_bounds` precede `_skeleton()` e `set_bounds()`; pan/zoom/reset
precedem o backdrop; a prova de fase maior precede a validação final. Nenhuma etapa
exige redescobrir a arquitetura — todos os caminhos, valores e linhas de referência
estão citados acima.*
