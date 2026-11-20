# PLAN.md — Sistema de Transição e Navegação entre Telas — Arc Impact

> Documento de planejamento. Nenhuma implementação foi feita até aqui.
> Decisão final consolidada: `[Game] <- [Home] -> [Settings]` deslizante com fundo estático + `[Levels]` fora (destrutivo, como hoje).

## 0. Resumo executivo

### Conceito

Substituir trocas abruptas de cena por transições animadas onde os elementos das telas deslizam horizontalmente enquanto o background permanece estático. A transição cobre o tempo de carregamento — sem tela de loading convencional (jogo offline e leve).

### Decisão final de escopo (confirmada)

```text
(-1,0) Game  <-  (0,0) Home  ->  (+1,0) Settings   (deslizante, fundo estático)

[Levels] fora — troca destrutiva, como é hoje
```

- **Dentro do novo sistema (deslizante):** `Home`, `Game`, `Settings`.
- **Fora do novo sistema (destrutivo):** `Levels` continua `screens/levels.tscn` exatamente como hoje — clicar em Fases destrói a cena atual e monta Levels do zero.
- Botão **Fases destrói o Main sempre**, na Home e no popup do Game. Clicou em Fases = saiu da partida, sem preservar fase em memória. Voltar de Levels sempre reconstrói o `Main` do zero.
- Eixo vertical reservado `(0,±1)` não será implementado agora. `ScreenNavigator` usa grade `Vector2i` (custo zero), mas só o eixo X é usado.

---

## 1. Diagnóstico da arquitetura atual

### 1.1 Engine e configuração base

- **Godot 4.7, renderer `mobile`**, `stretch/mode="canvas_items"`, `aspect="expand"`, viewport base `1280x720` (`project.godot`).
- Cena principal atual (`run/main_scene`): `res://screens/intro.tscn`.
- **Autoloads:** `BackgroundMusic` (`background_music_manager.gd`) e `InterfaceSounds` (`interface_sound_manager.gd`). Sobrevivem a `change_scene_to_file` — é por isso que música e cliques atravessam as trocas hoje.
- `SettingsManager` / `SaveManager` são `class_name` estáticos (fora da árvore). Estado persistente independente de cena.

### 1.2 Telas existentes

| Tela | Arquivos | Responsabilidade |
|---|---|---|
| Intro | `screens/intro.tscn` / `.gd` | Logo + `AnimationPlayer` (fade 3s) → `home.tscn`. Sem lógica. |
| Home | `screens/home.tscn` (sem script próprio) | `CenterContainer` com `Play`, `Levels`, `Settings`. Botões navegam sozinhos. |
| Levels | `screens/levels.tscn` / `.gd` | Header Voltar + `LevelMap`, subtítulo de progresso, hint de fase bloqueada. Lê `SaveManager`, escreve `game.gd.requested_level / return_scene`, troca para `game.tscn`. |
| Settings | `screens/settings.tscn` / `.gd` | Painel Música/SFX/Inverter-Y/Tipo-controle. Lê/escreve `SettingsManager` no `_ready`. Voltar → `home.tscn`. |
| Game | `screens/game.tscn` / `.gd` (~446 linhas) | Tela pesada: `WorldArea/World/Level + Cannon + GameCamera`, `BackgroundLayer(-1)`, `UILayer(10)` com `WorldHitArea`, `ControlsArea`, `Hud`, `GamePopup`. Gera fase via `FastLevelGenerator + LevelBuilder.build()`, prewarm de `BulletTrail`, limpa grupos `bullets/bullet_trails/shards/impact_texts`, gerencia pause, câmera, input touch/mouse/teclado. |

### 1.3 Navegação atual — troca destrutiva

Toda navegação é `get_tree().change_scene_to_file(...)`, que é *deferred* e libera a cena antiga. Mapeado em 9 pontos:

- `play_button.gd` → game (zera `requested_level`, `return_scene=home`).
- `levels_button.gd` → levels.
- `settings_button.gd` → settings.
- `levels.gd`: voltar → home; selecionar fase → game (com `requested_level` + `return_scene=levels`).
- `settings.gd` → home.
- `game.gd`: popup home → `return_scene`; popup levels → `LEVELS_SCENE`.
- `intro.gd` → home.

Estado de sessão improvisado via **estáticos em `game.gd`** (`requested_level`, `return_scene`). Funciona porque o script fica em cache no `ResourceLoader`, mas é frágil e deve desaparecer com o novo sistema.

### 1.4 Background atual — não é compartilhado

- `components/background/home/Background.tscn` ≅ `game/Background.tscn`: `background.jpg` + `BackgroundShapes` (22 formas procedurais animadas via `_draw`, com `seed_value`, wrap, `size_changed`).
- `components/background/levels/Background.tscn` (reusado por `settings.tscn`): `levels.jpg` estático, sem shapes.
- Cada tela instancia seu próprio background → troca de cena **recria e reinicia** o fundo. Viola a regra "background estático".
- `BackgroundShapes._resolve_area()` mede o `Control` pai ou o viewport — funcionará bem num background único global, precisa só de um pai full-rect estável.

### 1.5 O que pode ser reutilizado

- `BackgroundShapes` + `background.jpg`: fundo "canônico" (home + game). Candidato a fundo global.
- `BackgroundMusicManager` / `InterfaceSoundManager`: independentes da árvore, **nenhum tratamento necessário**.
- `SaveManager` (atômico tmp+rename+bak, monotônico) e `SettingsManager`: desacoplados, só precisam de ponto `refresh/enter` ao exibir painel.
- `LevelMap.setup()`, `Game.load_level()`, `GamePopup`: mantidos, só mudam de "rodar no `_ready` da cena" para "rodar no `enter()` do painel" (Game/Home/Settings) — Levels continua no `_ready`.
- Não há hoje nenhum `ScreenManager`, `Tween` de navegação ou overlay de bloqueio — tudo será novo, mas pequeno.

### 1.6 Conflitos previstos

1. `Game.tscn` tem `CanvasLayer(-1)` e `UILayer(10)` internos. Sob um `Main` global, o `BackgroundLayer` interno duplicaria o fundo.
2. `change_scene_to_file` libera a cena antiga. Todo esse modelo sai de Home/Game/Settings; os estáticos `requested_level/return_scene` deixam de fazer sentido.
3. `levels.gd._wait_for_layout()` + `map.setup()` medem `map.size`. Painel invisível (`visible=false`) tem tamanho zero → medição falha. Painéis fora da tela **devem ficar `visible=true` deslocados**, não escondidos.
4. `Game` usa `get_tree().paused` (popup pause). Durante transição a árvore não pode estar pausada, senão o `Tween` trava — transição e pause precisam de exclusão mútua.
5. Game mistura `Control` (UI) + `Node2D` (mundo) + `Camera2D` com `set_view_area(WorldHitArea)`. Mover o Game para dentro de um painel deslocado exige que câmera e `WorldHitArea` continuem medindo o viewport, não a posição do painel.
6. Dois mecanismos de navegação vão conviver (slide dentro do Main + destrutivo para Levels). Risco de chamar `Navigator` quando o Main já foi liberado (duplo-clique em Fases).

---

## 2. Arquitetura proposta

Uma **cena raiz persistente** substitui as trocas destrutivas **apenas** para Home/Game/Settings:

```text
Main (Control full-rect, nova main_scene)
├── Background (global, único, estático — background.jpg + Shapes)
├── ScreenHost (Control full-rect, clip_contents=true)
│   ├── HomePanel (instância de home, sem Background próprio)
│   ├── GamePanel (instância de game, sem BackgroundLayer próprio, lazy)
│   └── SettingsPanel (instância de settings, sem Background próprio)
├── BlockInput (Control full-rect, mouse_filter=STOP, visível só durante transição)
└── ScreenNavigator (script em Main, único dono da navegação interna)
```

Fora disso, isolado:

```text
Levels (screens/levels.tscn — cena independente, como hoje)
├── Background próprio (levels.jpg)
├── Dim / Header / LevelMap / Hint
```

- `Main` vira o `run/main_scene`. `Intro` passa a chamar `main.tscn` (com args `start=home`) em vez de `home.tscn`.
- Cada tela interna vira um **painel full-rect** filho de `ScreenHost`. Navegar = animar a **posição dos painéis** com `Tween`, fundo parado.
- `ScreenNavigator.gd` centraliza: `navigate_to(id, params)`, `go_back()`, flag `_navigating`, recusa de cliques concorrentes, cálculo de offsets pelo tamanho real do viewport.
- `Levels` **não** é filho de `ScreenHost`, não tem `enter()/exit()`, não participa de `Tween`.
- Telas internas expõem interface mínima opcional (duck-typing, sem herança obrigatória):

```gdscript
func enter(params: Dictionary) -> void
func exit() -> void
```

Se não existir, o navegador só move o painel.

---

## 3. Organização espacial das telas

```text
(-1,0) Game  <-  (0,0) Home  ->  (+1,0) Settings

[Levels] = outra cena, fora desse espaço
```

- **Horizontal (único eixo implementado):** `Game <- Home -> Settings`.
- Home→Game: `delta = (-1,0)` → painéis movem `+W` (sensação de empurrar para a direita, revela painel da esquerda).
- Home→Settings: `delta = (+1,0)` → painéis movem `-W` (revela painel da direita).
- Posição = `índice_grid * viewport_size`. Ex.: Game em `Vector2(-W, 0)`, Settings em `Vector2(+W, 0)`. Painel visível sempre converge para `Vector2.ZERO`.
- Mover **cada painel**, não o host (evita arrastar o fundo por acidente).
- Responsividade: recalcular em `get_viewport().size_changed`. `W/H` vêm de `get_viewport_rect().size`, nunca de constante 1280x720. Como `stretch=expand`, painéis usam anchors full-rect.
- Vertical não implementado nesta etapa. Grade `Vector2i` preparada para `(0,±1)` futuro, sem custo.

---

## 4. Estratégia de persistência do background

- **Um único `Background`** filho direto de `Main` (fora do `ScreenHost`), `mouse_filter=IGNORE`, full-rect.
- Conteúdo: `background.jpg` (usado por home+game) + `BackgroundShapes` existente, sem alteração de lógica — só reparentado. Identidade visual dominante, animação autônoma.
- Remover de cada tela interna seu nó `Background`: home, game (`BackgroundLayer`), settings (`levels.jpg`).
- Manter apenas os `Dim` (`ColorRect` semitransparente) **dentro** dos painéis quando necessário — pertencem ao painel (legibilidade), deslizam junto.
- `levels.jpg` mantido **apenas** em `levels.tscn`. Quando entrar em Levels, o fundo global é destruído junto com o Main; quando voltar, é recriado. Flash inevitável nesse ponto = comportamento atual preservado, não bug.
- `levels.jpg` aposentado do Settings (Settings passa a usar o fundo global). Unificação total (aposentar `levels.jpg` de Levels também) fora de escopo.
- `BackgroundShapes` continua ouvindo `size_changed` — como o pai nunca se move, o efeito "fundo parado" é automático.

---

## 5. Estratégia de instanciação, carregamento e descarregamento

Jogo offline e leve → **manter painéis do Main instanciados após a primeira criação**. Justificativa:

| Painel | Custo | Decisão |
|---|---|---|
| Home | 3 TextureButtons + VBox | Instanciar no `_ready` do Main, nunca liberar. `enter()` no-op (botões stateless). |
| Settings | Painel + sliders | Idem. `enter()` relê `SettingsManager` (`set_pressed_no_signal`, volumes). |
| Game | Mundo procedural + Cannon + Câmera | **Lazy na primeira navegação**, depois persistente. `enter(params)` chama `load_level()` só se `params` pedir fase nova. Texturas/scripts são `preload` compartilhados. Manter instanciado evita recompilar pipelines de luz e regenerar sem necessidade. Memória ≈ uma fase por vez — irrelevante para offline. |
| Levels | Header + LevelMap | **Fora do Main.** Monta/destrói via `change_scene_to_file` como hoje. `Main` inteiro morre junto ao ir para Levels. |

- Carregamento **durante** a transição interna: `navigate_to(game)` faz `await panel.enter(params)` (que dispara `load_level`) **em paralelo/como pré-condição** do `Tween` de 0,38s. Geração procedural + `await builder.build()` (cede 1 `physics_frame`) cabe na janela; se `enter` demorar mais, o tween espera o `enter` terminar antes de começar (sem tela incompleta).
- Nenhum `queue_free` de painel interno na navegação normal. `exit()` do Game só pausa sons transitórios (`ImpactSoundManager.stop_all`, já existente) e congela input, nunca destrói a fase.
- `Main → Levels`: destrói tudo (`Level`, transitórios `bullets/trails/shards/impact_texts`, Navigator, fundo global). Sem resume.
- `Levels → Main`: reconstrói do zero via `MainStartupArgs` (ver §6). Se `start_level > 0`, `Game.enter` roda antes do primeiro frame visível.

---

## 6. Fluxo detalhado das transições

### 6.1 Proposta de API do Navigator (não implementar neste documento)

```gdscript
class_name ScreenNavigator
static var start_target := "home"  # "home" | "game" — consumido por Main._ready
static var start_level := 0        # 0 = progresso atual, N = fase vinda de Levels
func navigate_to(id: String, params: Dictionary = {}) -> void
func go_back() -> void
```

Estes estáticos substituem `game.gd.requested_level / return_scene` (que viviam no ResourceLoader e devem ser removidos).

### 6.2 A. Home → Settings (slide horizontal)

1. `SettingsButton` chama `Navigator.navigate_to("settings")` + `pluck()` (como hoje, antes da navegação).
2. Navigator verifica `_navigating` → se `true`, ignora (sem fila; evita duplo-toque). Seta `_navigating=true`, mostra `BlockInput` (`mouse_filter=STOP` consome cliques; `Game._unhandled_input` e `shoot()` também checam a flag).
3. Resolve direção: `delta = grid[target] - grid[current]` (ex. `(+1,0)` → deslizar para esquerda).
4. `await Settings.enter()` → relê volumes/invert/tipo — <1 frame. Painel-alvo já posicionado offscreen (`visible=true`).
5. Um único `Tween` (`set_parallel(true)`): `Home: 0 → -W`, `Settings: +W → 0`. Duração **0,38s**, `TRANS_CUBIC`, `EASE_IN_OUT`. Câmera e `BackgroundShapes` não participam.
6. `await tween.finished` → `current=settings`, `Home.exit()` (no-op), esconde `BlockInput`, `_navigating=false`.
7. Volta idêntica com `delta` negado, sem rebuild. Sliders preservados (nós nunca liberados).

### 6.3 B. Home ↔ Game (slide horizontal)

Mesmo fluxo de A, com `delta = (-1,0)`:

1. `PlayButton` → `navigate_to("game")` (+ `pluck()`).
2. `await Game.enter(params)` → `load_level()` só se `params` pedir fase nova ou primeira criação lazy.
3. Tween `Home: 0 → +W`, `Game: -W → 0`, 0,38s.
4. Popup Home do Game → `navigate_to("home")` (slide inverso, sem rebuild, fase mantida em memória — pause continua disponível).
5. Mesmos parâmetros de animação dos dois lados (ambos horizontais primários). Não diferenciar Game de Settings.

### 6.4 C. Home → Levels (destrutivo, inalterado)

1. `LevelsButton` → `pluck()` → `change_scene_to_file("res://screens/levels.tscn")`.
2. Engine libera `Main` inteiro (Home/Game/Settings + fundo global + Navigator).
3. `levels.tscn` monta como hoje: `_ready` lê save, `await _wait_for_layout + map.setup()`.
4. Nenhum `Tween`, nenhum `BlockInput`, nenhum `enter`.
5. Proteção: `LevelsButton` desabilita-se após 1º clique (evita duplo `change_scene` com Main morrendo).

### 6.5 D. Game (popup) → Levels (destrutivo, confirmado)

1. Botão Fases do popup: despausa (`paused=false`) **antes** da troca (senão Levels nasce pausada — código atual já faz isso, manter).
2. `change_scene_to_file(levels.tscn)` direto, descartando `Level` e transitórios junto com o `Main`.
3. Sem `MainStartupArgs`, sem lembrar origem. Levels sempre volta para Main.

### 6.6 E. Levels → Main (reconstrução)

1. Voltar: `ScreenNavigator.start_target = "home"` → `change_scene_to_file(main.tscn)`.
2. Selecionar fase N: `ScreenNavigator.start_target = "game"; start_level = N` → `change_scene_to_file(main.tscn)`.
3. `Main._ready()` consome e zera os estáticos, instancia Background global + Home/Settings, lazy-Game se `start_target==game`, posiciona tudo offscreen exceto o alvo **sem animação inicial**.
4. Se `start_level > 0`: `Game.enter({level})` roda `SaveManager.seed_for_level()` + `load_level()` antes do primeiro frame visível — já nasce pronto (evita mostrar Home por 1 frame e depois deslizar).

---

## 7. Componentes, cenas e scripts

### 7.1 Criar (2 arquivos)

- `screens/main.tscn` — `Main` + `Background` global + `ScreenHost` + `BlockInput`.
- `screens/screen_navigator.gd` — grade 3 posições (X apenas), `navigate_to/go_back`, tween, lock, reposicionamento em `size_changed`, `MainStartupArgs` estáticos.

### 7.2 Modificar

- `screens/home.tscn`: remover nó `Background`; `LevelsButton` volta a `change_scene_to_file(levels)`; `PlayButton` e `SettingsButton` viram `Navigator.navigate_to`.
- `screens/settings.tscn` / `.gd`: remover `Background(levels.jpg)`; Voltar vira `Navigator.navigate_to("home")`; adicionar `enter()` com refresh do `SettingsManager`.
- `screens/game.tscn` / `.gd`: remover `BackgroundLayer`; popup Home vira `navigate_to("home")`, popup Levels vira `change_scene_to_file(levels)`; `enter({level})` substitui estáticos `requested_level/return_scene`; guardas de `_navigating` em `shoot/pause/_unhandled_input`.
- `screens/levels.gd`: trocar `HOME_SCENE/GAME_SCENE` por `MAIN_SCENE + ScreenNavigator.start_*`; trocar `GAME_SCRIPT.requested_level` por `ScreenNavigator.start_level`.
- `screens/intro.gd`, `project.godot`: apontar `main_scene` / destino para `main.tscn`.
- `components/play-button/`, `levels-button/`, `settings-button/`, `game_popup.gd`: trocar `change_scene_to_file` internos (exceto os 4 pontos Levels que permanecem destrutivos — documentar no código quais são slide e quais são destrutivos).
- Testes em `components/*/tests/` que usam `change_scene_to_file` (ex. `background_music_test.gd`, `game_popup_test.gd`): instanciar `Main` ou mockar Navigator.

### 7.3 NÃO tocar (mantido igual)

- `screens/levels.tscn` (layout, `levels.jpg`, `Dim`, `LevelMap`), `level_map.gd`, `save_manager.gd`, `SettingsManager`, áudios, `background_shapes.gd`, gerador procedural, câmera, HUD.
- Áudio: nenhum tratamento. Música/SFX são autoloads; transição não para nem reinicia nada. Opcional futuro: whoosh de ~150ms via pool do `InterfaceSoundManager` — avaliar, não implementar agora.

### 7.4 Mapa da navegação final (onde fica cada `change_scene_to_file`)

Permitidos (4 pontos, todos envolvendo Levels):

1. `LevelsButton (Home)` → levels.
2. `GamePopup (botão Fases)` → levels.
3. `levels.gd Voltar` → main.
4. `levels.gd Selecionar fase` → main com args.

Todo o resto (Home↔Game↔Settings, popup Home, Settings Voltar) é `Navigator`. `grep change_scene_to_file` deve retornar só esses 4 pontos + referências em docs/skills.

---

## 8. Riscos, conflitos e cuidados

1. **Perda de estado Main→Levels→Main (comportamento especificado, não bug):** se o jogador estava no meio de uma fase, vai para Levels e volta, a fase é regenerada (não é resume). Documentado e confirmado.
2. **Dois sistemas convivendo:** chamar `Navigator` quando o Main já foi liberado (clique duplo em Fases). Mitigação: desabilitar `LevelsButton` após 1º clique; `navigate_to` recusa se `_navigating`.
3. **Painel invisível vs. offscreen:** usar `visible=true` deslocado. `visible=false` quebra `LevelMap.setup()` e `BackgroundShapes._resolve_area()`.
4. **Game pausado + transição:** proibir `navigate_to` com `get_tree().paused==true` (exceto resume interno); tween padrão trava pausado. `GamePopup → Levels` despausa antes da troca.
5. **Duplo-background do Game:** esquecer de remover `BackgroundLayer` interno duplica draw e reintroduz movimento. Checklist obrigatório na Etapa 1.
6. **Medida de viewport:** nunca fixar 1280x720 no Navigator; usar `get_viewport_rect().size` + `size_changed` (padrão já usado em `game.gd` e `background_shapes.gd`).
7. **Input fantasma:** além do `BlockInput`, `Game._unhandled_input` e `shoot()` com early-return em `_navigating`; botões saem da área de clique pelo deslocamento, mas o overlay garante.
8. **Câmera do Game:** `set_view_area(WorldHitArea)` mede via `get_global_transform_with_canvas()` — validar que com painel em `position != 0` durante o tween a câmera não deriva; se derivar, congelar `game_camera` (`set_process(false)`) durante o tween.
9. **Testes:** `background_music_test.gd` e `game_popup_test.gd` usam `change_scene_to_file(HOME/GAME)` — precisam mirar `main.tscn` + args.
10. **QA de fundo:** validar que o flash `background.jpg ↔ levels.jpg` ocorre **só** nas bordas Levels, nunca em Home↔Game↔Settings.
11. **Áudio:** nenhum cuidado. Autoloads atravessam ambos os mecanismos. Não adicionar whoosh nesta etapa.

---

## 9. Etapas de implementação (ordem lógica)

1. **Etapa 0 — Main com 3 painéis, troca instantânea.**
   Criar `main.tscn` + `screen_navigator.gd` mínimo (reposiciona sem tween). Main abre na Home, fundo único, Levels acessível por corte.
   *Conclusão:* sem fundo duplicado, sem regressão visual em 1280x720 e em uma resolução expandida (ex. retrato).

2. **Etapa 1 — Slide H Home↔Game↔Settings.**
   Tween 0,38s `TRANS_CUBIC/EASE_IN_OUT` + lock `_navigating` + `BlockInput`. Remover `Background` de home/settings e `BackgroundLayer` de game.
   *Conclusão:* fundo parado, duplo-clique não empilha navegação, 3 proporções de tela (16:9, 19.5:9, retrato).

3. **Etapa 2 — `enter()` + `MainStartupArgs`.**
   Migrar Settings-refresh e Game-load para `enter`; trocar `requested_level/return_scene` por `ScreenNavigator.start_target/start_level`.
   *Conclusão:* Home→Game direto funciona; Levels→fase N nasce pronta sem flash de Home; voltar preserva scroll/pause sem rebuild (dentro do Main).

4. **Etapa 3 — Religar Levels destrutivo.**
   Botões Fases (Home + popup) e Voltar/Selecionar de Levels mirando `main.tscn` + args. Documentar no código slide vs. destrutivo.
   *Conclusão:* `grep change_scene_to_file` só nos 4 pontos Levels; resto é Navigator.

5. **Etapa 4 — Limpeza e testes.**
   Atualizar `main_scene`, ajustar testes (`background_music`, `game_popup`, `level_select`), remover estáticos obsoletos.
   *Conclusão:* suite de testes passa; sem referências mortas a `requested_level/return_scene`.

6. **Etapa 5 — Polimento e validação.**
   Easing final, teste spam de botões, pause→Fases, vitória→Levels→Game (save monotônico intacto: replay não regride, vitória persiste antes da transição), teste no APK.
   *Conclusão:* 60fps percebidos, sem clique atravessando, sem perda de progresso, flash de fundo só nas bordas Levels.

---

## Apêndice — Histórico de decisões

- Plano original previa 4 painéis deslizantes (`Game <- Home -> Levels`, Settings vertical). Substituído pela troca solicitada.
- Troca solicitada: Levels fora das transições (destrutivo, tudo igual), Settings assume slot horizontal da direita: `[Jogo] <- [Inicial] -> [Configurações]`.
- Confirmado: Fases destrói mesmo nos dois pontos (Home e popup). Sem resume implícito.
- Em aberto para implementação futura (não decidir agora): unificar `levels.jpg` → `background.jpg + Shapes`; whoosh de transição; eixo vertical `(0,+1)`.
