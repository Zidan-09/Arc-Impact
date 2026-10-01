# Plano — Correção estrutural da física/colisão (visual × físico + tunneling)

> Status: SOMENTE DIAGNÓSTICO E PLANO. Nenhum código foi alterado.
> Escopo: `Floor`, `Obstacle` (vidro/pedra/metal), `Target`, `Cannon`, projétil/bullet e pipeline de geração.
> Fora do escopo: HUD, câmera, controles, regras de gameplay, geração de fases (além do estritamente necessário).
> O capítulo anterior deste arquivo (refatoração composition-first) foi preservado abaixo, intacto.

---

## 1. Causa raiz (resumo)

Duas causas independentes, que se somam de forma intermitente:

**Causa A — Tunneling por ausência de CCD (principal).** O projétil voa a até 2000 px/s = **33,3 px por physics tick** (60 Hz padrão; `project.godot` não altera ticks nem gravidade — vale o default 980/60). Nenhum `RigidBody2D` do projeto configura `continuous_cd` (grep: zero ocorrências) e a bala no jogo roda com `contact_monitor = false` (só `SimulationWorld` liga, e só para contar ricochetes). Com deslocamento/tick maior que a menor dimensão do collider no eixo do movimento, o corpo discreto "pula" o collider: sem colisão física E sem callback. É intermitente por construção (depende do alinhamento tick × trajetória × fase), exatamente o sintoma relatado.

**Causa B — Dupla fonte de verdade na detecção (arquitetural).** A resposta física vem do contato corpo-a-corpo no servidor de física, mas a lógica de gameplay (`hit()`, destruição, `target_hit`) vem de **dois sistemas `Area2D` discretos e independentes**: o `HitDetector` da bala (para pedra/metal/target) e o `HitBox` do vidro — e o `StaticBody2D` do vidro **não tem `CollisionShape2D` próprio** (corpo vazio, só o `Area2D` filho detecta). Dois sistemas discretos podem discordar no mesmo tick: rebateu sem registrar (pedra não racha, vitória do alvo não conta) ou registrou sem rebater. O vidro depende 100% de `Area2D`, que também sofre tunneling.

**Não é causa:** `scale` em múltiplos níveis (verificado: aplicação única na raiz de cada instância; §3), `collision_layer/mask` (tudo default 1/1, coerente), gravidade/ticks (defaults consistentes entre jogo, `SimulationWorld` e solver analítico).

---

## 2. Cadeia visual → física por elemento (medido no código)

Medidas de arte via decodificação dos PNGs; colliders lidos dos `.tscn`.

| Elemento | Visual real (base, escala 1) | Collider base | Relação | Transformação aplicada | Veredito |
|---|---|---|---|---|---|
| `Floor` (`floor.tscn`: `StaticBody2D` + `CollisionShape2D` 500×500) | `floor.png` 500×500 full-bleed | `RectangleShape2D` 500×500 | 1:1 exato | `scale 0.2` na raiz (`LevelBuilder.build_floor`/`build_ground`, `FloorShapes.SCALE`) → tile 100×100, grade passo 100 | ✅ coerente |
| Pedra (`stoneObstacle.tscn`: `StaticBody2D` + `HitBox` 500×500) | `stone_square.jpg` 500×500 | `RectangleShape2D` 500×500 | 1:1 | `scale` da `ObstacleDefinition` na raiz (`LevelBuilder.build` linha 38; `PatternLibrary.BLOCK_SCALE` 0.2 → 100×100) | ✅ coerente |
| Metal (`metalObstacle.tscn`, idem 548×548) | `metal_square.jpg` 547×547 | `RectangleShape2D` 548×548 | 1 px dif. | idem (0.2 → ~110×110) | ✅ coerente |
| Vidro (`glassObstacle.tscn`: `StaticBody2D` **sem shape** + `HitBox: Area2D` 952×934) | `glass_square.jpg` 952×935 | `RectangleShape2D` 952×934 (só no `Area2D`) | 1:1, mas **sem corpo físico** | idem (`GLASS_SCALE` 0.1 → ~95×93; poste 0.05 → ~48×47) | ⚠️ coerente em tamanho, mas detecção 100% `Area2D` discreta (Causa B) |
| `Target` (`target.tscn`: `StaticBody2D` com `scale 0.2` **no próprio tscn** + `CollisionPolygon2D` 114×474) | sprites ~144×485 (×1.32) → instanciado **~29×97 px** | polígono → instanciado **22,8×94,8 px** | visual ~6 px mais largo (3 px/lado) | nenhuma no builder (`LevelBuilder.build` só define `position`/`rotation_degrees`); guides também não sobrescrevem → sempre 0.2 | ⚠️ divergência real de ~26% na largura (Causa C2); `TargetDefinition.DEFAULT_SIZE` 80×80 ≠ corpo 23×95 (só afeta validador — conservador, não causa atravessamento; solver usa `TARGET_BODY` correto) |
| Bala (`bullet.tscn`: `RigidBody2D`, corpo r=46,17, detector r=56, sprite 0.3) | arte real: círculo Ø302 px dentro do canvas 500 → Ø45,3 px @sprite 0.3 | corpo Ø92,3 px base | física ~2% maior que a arte | `apply_cannon_scale(global_scale)` reescala raios + sprite (0.2 no jogo → corpo Ø18,5 px, detector Ø22,4 px, arte Ø18,1 px) | ✅ coerente; ⚠️ **pequena demais para a velocidade** (Causa A) |
| `Cannon` | — (sem corpo físico próprio além das paredes do cano) | `SegmentShape2D` paredes filhas de `BarrelPivot` | herda `cannon.scale` (0.2 jogo, 0.3 guides) | `game.gd:87` aplica `cannon_scale` da composição | ✅ coerente; fora da cadeia do bug |

Tabela de vulnerabilidade a tunneling (deslocamento/tick vs menor dimensão, potência máxima 2000 px/s → 33,3 px/tick; mínima 600 px/s → 10 px/tick):

| Collider no mundo (@escalas reais) | Menor dimensão | 33 px/tick (pot. máx) | 10 px/tick (pot. mín) |
|---|---|---|---|
| Target 23×95 | 23 px | 🔴 pula | 🟢 detecta |
| Vidro poste 0.05 (~48×47) | ~47 px | 🟡 rasante pula | 🟢 detecta |
| Vidro gate 0.1 (~95×93) | ~93 px | 🟢 detecta (3 ticks) | 🟢 detecta |
| Pedra/metal/floor 100–110 px | 100 px | 🟢 corpo não pula; 🟡 penetra fundo | 🟢 detecta |

Isso explica cada sintoma: atravessa `Target` (sempre fino); atravessa `Obstacle` (só os finos: poste de vidro); "depende da escala/fase" (só fases com peças finas no caminho falham); "potência máxima" (Cenário 4 é o crítico); "posições diferentes da aparente" (detector Ø22 px vs corpo Ø18 px vs arte Ø18 px + 3 px/lado do alvo).

---

## 3. Onde a inconsistência é introduzida (arquivos e linhas)

1. `components/bullet/bullet.tscn` — `RigidBody2D` sem `continuous_cd`, sem `contact_monitor`. É o único corpo rápido do jogo e nasceu sem proteção contra tunneling.
2. `components/bullet/bullet.gd` — lógica de hit da bala contra pedra/metal/target chega via `$HitDetector.body_entered` (`Area2D` Ø22 px no mundo, discreto). O contato físico real (que produz o rebote) é outro sistema. Discordância = rebote sem `hit()` (pedra HP2 não racha; `target_hit` não emite mesmo com rebote visível) ou `hit()` sem contato.
3. `components/obstacles/glass/glassObstacle.tscn` — `StaticBody2D` raiz sem `CollisionShape2D`; detecção exclusiva via `HitBox: Area2D` → `glass_obstacle.gd:28` (`_on_hit_box_body_entered`). Em corda curta (< 33 px, poste 0.05 em rasante) o `body_entered` nunca dispara: atravessa sem `*= 0.85`, sem shards, sem registro.
4. `components/obstacles/obstacle.gd:50-74` — `play_hit_animation()` faz tween de `scale` na **raiz do `StaticBody2D`** (×1,08 por 0,3 s). A pedra sobrevive ao 1º hit com o collider pulsando: divergência visual×física transitória real (pequena, mas existe e é evitável).
5. `components/target/target.tscn:8-9,20,25` — `scale 0.2` fixo na raiz + sprites com escala própria (~1,32) → arte 29 px vs polígono 22,8 px de largura. Raspão na borda visual passa sem colidir.
6. `components/cannon/cannon.gd:124-136` (`shoot()`) — ordem `add_child → apply_cannon_scale → set position/velocity` está correta; `game.gd:87` aplica a escala da composição ao canhão. Sem dupla aplicação de escala em nenhum caminho (`LevelBuilder`, `SimulationWorld._spawn`, guides: todos definem `scale` uma única vez na raiz).
7. `components/level/level_validator.gd:189-190` (`_target_rect` 80×80) vs `fast_level_generator.gd:40` (`TARGET_BODY` 23×95) — duas fontes para "tamanho do alvo". Hoje o erro é conservador (não causa o bug), mas viola o princípio da fonte única.

---

## 4. Tunneling × collider incorreto (separação exigida)

- **Collider incorreto em relação ao visual:** SIM, mas pequeno e localizado — só o `Target` (Causa 5 acima, ~3 px/lado) e o pulse transitório do `Obstacle` (Causa 4). Todo o resto é 1:1.
- **Projétil atravessando collider correto:** SIM, e é o dominante — Causa A (física discreta sem CCD) + Causa B (`Area2D` como única detecção do vidro e como detecção lógica da bala). Os dois problemas existem simultaneamente e precisam de correções distintas (§5, itens 1–3 vs item 4).

---

## 5. Arquitetura da correção (fonte única de verdade)

```text
posição varrida da bala por tick (raycast prev→atual, bodies + areas)
		↓
contato físico do corpo (CCD cast-shape + contact_monitor)
		↓
UM roteador em bullet.gd chama hit() / emite sinais
```

Sem `Area2D` como decisor, sem `scale` animado em corpo físico, sem dois tamanhos de alvo.

| # | Arquivo | Ação | Motivo |
|---|---|---|---|
| 1 | `components/bullet/bullet.tscn` | `continuous_cd = 2` (cast-shape), `contact_monitor = true`, `max_contacts_reported = 8` | Elimina o tunneling físico (floor, pedra, metal, corpo do alvo). Custo mobile irrelevante (1 corpo rápido por vez). |
| 2 | `components/bullet/bullet.gd` | Conectar `body_entered` do **corpo**; a cada physics tick, `intersect_ray` (ou `cast_motion`) do segmento `prev→current` com `collide_with_areas = true`; rotear o primeiro hit de gameplay por corpo (deduplicar por instância); **remover o nó `HitDetector`** | Uma fonte de verdade que enxerga bodies E o `HitBox` do vidro mesmo quando o tick pula o collider. Mantém a mecânica do vidro (atravessa `*= 0,85`, sem rebote — o `StaticBody` dele continua sem shape) sem depender de `body_entered` discreto. Idempotência já existe (`is_broken`/`is_processing_hit`). |
| 3 | `components/obstacles/glass/glassObstacle.tscn` + `glass_obstacle.gd` | NADA (nenhuma mudança) | Com o item 2, o `HitBox` vira alvo passivo do raycast; o corpo vazio deixa de ser problema. Zero refatoração nos obstáculos. |
| 4 | `components/obstacles/obstacle.gd:50-74` | Animar a escala dos **sprites filhos** em vez de `self.scale` | Collider estável durante o feedback visual; preserva o efeito atual pixel a pixel. |
| 5 | `components/target/target.tscn` (polígono) | Alargar o `CollisionPolygon2D` ~3 px por lado na largura (ou estreitar os sprites para a arte casar com 22,8 px) | Elimina a única divergência permanente visual×física. Medir contra a bbox da arte (86×476 base). |
| 6 | `components/level/material_rules.gd` | +`target_size() -> Vector2(114, 474)` (base, escala 1); `level_validator._target_rect` e `TARGET_BODY` do solver passam a derivar dele | Uma fonte para o tamanho do alvo (validador, solver analítico e cena). Sem mudar nenhum limiar de gameplay. |
| 7 | `components/level/tests/` | Novo teste headless: N tiros a potência máxima contra alvo fino + poste 0.05 via `SimulationWorld`, contando atravessamentos sem registro (deve ser 0 após a correção) | Regressão automática do bug intermitente; `SimulationWorld` já instancia as cenas reais. |

Não alterar: `Floor`, pedra, metal, `Cannon`, `Game.tscn`, câmera, HUD, controles, geração (composição/validador/solver intactos — o solver analítico já modela `BULLET_RADIUS`/dilatação e continua válido), regras de materiais, ricochete do alvo (segue emergente do `bounce 1.0`; com detecção unificada o `target_hit` passa a acompanhar deterministicamente o contato real).

---

## 6. Validação (cenários obrigatórios → como verificar)

- Cenário 1 (Floor): tiro direto ao chão em vários ângulos, pot. máx. Critério: nenhum atravessamento; sem "afundamento" profundo (CCD impede penetração > fração do tile). Debug: `Debug → Visible Collision Shapes` ligado, comparar sprite×shape quadro a quadro.
- Cenário 2 (Target): tiro direto no alvo de frente e de raspão. Critério: todo contato visual emite `target_hit` + ricochete com `bounce 1.0`; borda da arte (3 px/lado, item 5) agora colide.
- Cenário 3 (Obstáculos): vidro gate 0.1, poste 0.05, pedra HP1/HP2, metal. Critério: vidro sempre atenua `*= 0,85` + shards; pedra racha no 1º e destrói no 2º; metal rebate sem dano; zero atravessamento silencioso.
- Cenário 4 (Alta velocidade): pot. máx contra alvo fino e poste em ângulo rasante (pior caso: corda < 33 px). Critério: 100% dos contatos registrados (era o caso que mais falhava antes).
- Cenário 5 (Escalas): peças 0.05–1.0. Critério: física acompanha o visual em todas (escala continua aplicada uma vez na raiz; nada muda aqui — só confirmar).
- Cenário 6 (Procedurais): rodar N fases (ex. 20 seeds × fases 1/5/12/18) + teste headless do item 7. Critério: zero atravessamentos sem registro; vitória/derrota via `target_hit` inalteradas; suíte existente verde.

---

# Plano de Refatoração — Geração de Fases Reais em `Game.tscn`

> Escopo exclusivo: fazer `screens/Game.tscn` (+ seu pipeline de geração) produzir fases procedurais válidas segundo `docs/Levels.md`. Não alterar HUD, câmera, controles ou outras telas, salvo o estritamente necessário para instanciar/posicionar a fase. Nenhum código é alterado neste plano.
>
> Princípio norteador desta revisão: **o gerador constrói uma fase como uma composição intencional. As regras geométricas servem para garantir que essa composição seja válida, não para decidir sozinhas como a fase deve ser desenhada.**

---

# Objetivo

Substituir a geração atual (obstáculos esparsos sobre fundo plano, canhão fixo, sem `Structures`, sem `Floor` estrutural, sem rotação de `Target`) por um gerador **composition-first** que, dentro de `Game.tscn`, construa uma composição intencional:

```text
Floor
  ↓
Structures
  ↓
Obstacles
  ↓
Target
```

com `Cannon` integrado ao `Floor`, respeitando integralmente `docs/Levels.md`, mantendo determinismo (`seed, GENERATOR_VERSION, level_number` → mesma fase), orçamento de ~250–300 ms e jogabilidade validada.

Fluxo correto (o solver é o último portão, nunca o desenhista):

```text
Gerar composição
		↓
Validar estrutura
		↓
Validar regras
		↓
Testar jogabilidade (solver)
		↓
Aceitar ou rejeitar
```

É proibido o fluxo inverso (gerar objetos aleatórios e aceitar se o solver achar uma solução).

---

# Estado Atual

Como a geração funciona hoje (arquivos relevantes):

## Entrada — `screens/game.tscn` + `screens/game.gd`

- `Game.tscn` possui `WorldArea/World/Level: Node2D` (contêiner vazio da fase) e `WorldArea/World/Cannon` fixo em `Vector2(173, 523)`, `scale 0.2`, `base_shot_speed 2000.0`.
- `game.gd:load_level()` chama `FastLevelGenerator.generate(seed, level_number)` → recebe `LevelDefinition` → `LevelBuilder.build(level_node, def)` → reposiciona `cannon.position = def.cannon_position` (sempre `Vector2(173,523)` na prática) → conecta `target.target_hit`.
- Câmera/HUD/input não participam da geração e não devem ser tocados.

## Geração — `components/level/fast_level_generator.gd` (usado pelo jogo)

- Pipeline: `_skeleton()` → `_pick_archetype()` → `arch.place()` → `_clear_of_ground()` → `LevelValidator.validate()` + `validate_config()` → `solve_direct()` (balística analítica Euler 60 Hz, sem Nodes) → `DifficultyScorer`.
- `GROUND_TOP = 620.0`, `TARGET_MAX_Y = 575.0`: tudo deve ficar acima do chão fixo; ou seja, o gerador **assume chão plano** e rejeita qualquer coisa próxima a ele.
- `MAX_ATTEMPTS = 20`, `TIME_BUDGET_MS = 250`, determinístico via `RandomNumberGenerator` com `hash(seed:versão:fase)`.

## Geração legada — `components/level/procedural_level_generator.gd` + `components/level/level_solver.gd` + `components/level/simulation_world.gd`

- `ProceduralLevelGenerator` é o pipeline com física real (`LevelSolver` BFS + `SimulationWorld` com cenas reais). Hoje **não é usado pelo `Game`** (virou ferramenta offline/teste). `FastLevelGenerator._ultimate()` ainda o reutiliza só para o fallback.
- `LevelSolver.solve()` + `SimulationWorld.run_shot()` continuam válidos **apenas como prova de jogabilidade** (última etapa) e como ferramenta offline de calibragem. Não desenham fase.

## Dados — `components/level/level_definition.gd`, `obstacle_definition.gd`, `target_definition.gd`

- `LevelDefinition`: `seed, level_number, ammo, cannon_position` (fixa), ângulos/potência, `play_bounds/world_bounds (0,0,1280,720)`, `target: TargetDefinition`, `obstacles: Array[ObstacleDefinition]`, `solution`.
- `ObstacleDefinition`: `id, kind (glass|stone|metal), position, rotation_degrees (v1: só 0/90), scale`.
- `TargetDefinition`: **só `position + size (80×80 fixo)` — sem rotação.**
- **Não existe** `FloorDefinition` nem `StructureDefinition`. O `Floor` e as `Structures` não fazem parte dos dados. Tampouco existe qualquer registro de **intenção** (papel, grupo, âncora, função mecânica).

## Construção — `components/level/level_builder.gd`

- `build(world, def)`: instancia obstáculos via `MaterialRules.scene_for()`, instancia `Target` **sem rotação**, e chama `build_ground()` que coloca tiles planos `FLOOR_SCENE` em `y = 670`, `x = 50..1250` passo `100`, `scale 0.2`.
- `clear()` remove nós do grupo `level_spawned`. Cannon **não** é construído pelo builder (é nó fixo da cena, só reposicionado).

## Validação — `components/level/level_validator.gd`

Valida hoje: versão, ammo 1–4, canhão/alvo dentro de `play_bounds`, distância canhão–alvo ≥ 500, AABB dentro dos limites, exclusão do canhão (150 px), exclusão do alvo (100 px + `OVERLAP_TARGET`), corredor do muzzle, sobreposição entre obstáculos (margem 8 px), alvo cercado por metal (`TARGET_BOXED`), rotação (só 0/90), escala 0.05–1.0, coerência com `DifficultyConfig`. **Não valida nada de `Levels.md` estrutural** (floor, conectividade, structures, suporte do canhão).

## Dificuldade — `difficulty_table.gd` + `difficulty_config.gd`

- Bandas 1–3 (só vidro, 0–2 obs), 4–6 (vidro+pedra), 7–10 (+0–1 metal), 11–15 (1–3 metal, ≥1 ricochete), 16–20 (2–4 metal, ≥2 ricochetes). `max_obstacles` 3→12.
- Arquétipos atuais (`components/level/archetypes/`): `open_shot`, `glass_barrier`, `stone_gate`, `combo_order`, `blocked_direct`, `bunker`. Todos usam `place_on_lane / place_off_lane` (pontos aleatórios sobre/fora da reta canhão→alvo, com `fits()` anti-sobreposição). **Nenhum arquétipo conhece `Floor` ou `Structures`.**

## Componentes físicos

| Elemento | Cena / script | Física e geometria real |
|---|---|---|
| `Floor` | `components/floor/floor.tscn` (sem script) | `StaticBody2D`, `RectangleShape2D 500×500` → em `scale 0.2` = **tile 100×100**. Sprites `floor.png` + `floor_connection.png`. Empilhável em grade de 100 px. |
| `Cannon` | `components/cannon/cannon.tscn` + `cannon.gd` | `Node2D`; boca via `PIVOT_OFFSET (-2,-44) + MUZZLE_OFFSET (267,-48)` rotacionado (`muzzle_state_for()`). Ângulos `-20°..83°`. Bala reescalada por `apply_cannon_scale()` (raio base corpo 46.17 px, detector 56 px, sprite 0.3). |
| `Target` | `components/target/target.tscn` + `target.gd` | `StaticBody2D`, `CollisionPolygon2D` lateral (~470 px altura base ≈ 94 px em `scale 0.2`), `bounce 1.0`, sinal `target_hit`. Rotação livre no editor, mas **não serializada** hoje. |
| `Obstacle` vidro | `obstacles/glass/glassObstacle.tscn` + `glass_obstacle.gd` | `StaticBody2D` + `Area2D HitBox 952×934` (atravessável). 1 HP, `velocity_retain 0.85`, destrói e atravessa. Em `scale 0.1` ≈ 95×93 px. Mecânica: **quebrar**. |
| `Obstacle` pedra | `obstacles/stone/stoneObstacle.tscn` + `stone_obstacle.gd` | `StaticBody2D 500×500`, `bounce 1.0`, 2 HP (`stoneLife`), 1º hit racha (mantém corpo), 2º hit destrói com `*= 0.85` + 2 `physics_frame` de retenção. Em `scale 0.2` = 100×100 px. Mecânica: **desgastar**. |
| `Obstacle` metal | `obstacles/metal/metalObstacle.tscn` + `metal_obstacle.gd` | `StaticBody2D 548×548`, `bounce 1.0`, indestrutível, reflexão emergente do motor. Em `scale 0.2` ≈ 110×110 px. Mecânica: **ricochetear**. |
| `Structures` | `components/structure/Structure.tscn` (**sem script, sem colisão**) | Hoje é só `Node2D + Sprite2D` (`structure.png`). **Ambiguidade registrada**: nos guides ela é usada como viga/coluna visual entre obstáculos, mas sem corpo físico nada "sustenta" de fato. Decisão na implementação: ver § Arquitetura, decisão D3 (recomendado: manter como elemento de composição com contato geométrico validado, sem virar corpo físico na v1). |
| Projétil | `components/bullet/bullet.tscn` + `bullet.gd` | `RigidBody2D`; `HitDetector Area2D` chama `body.hit()`. Shards são ignorados pelos obstáculos. |
| Regras | `components/level/material_rules.gd` | Fonte única: `base_size()`, `scene_for()`, `velocity_retain()` (vidro 0.85, pedra 0.85, metal 1.0), `max_hp` (1/2/inf). |

---

# Problemas da Implementação Atual

Por que não atende `docs/Levels.md`:

1. **`Floor` decorativo, não estrutural.** `LevelBuilder.build_ground()` sempre gera a mesma faixa plana em `y=670`. Nunca sobe até canhão elevado nem retorna ao plano, nunca faz parte do desafio. Viola Levels §2.
2. **`Cannon` fixo.** `LevelDefinition.cannon_position` é sempre `(173, 523)`; não há alturas variadas nem sustentação. Viola Levels §§2–3.
3. **`Target` sem rotação e sem função compositiva.** `TargetDefinition` não tem rotação e o builder nunca rotaciona. Posição sorteada sem relação com o desenho. Viola Levels §4.
4. **Zero `Structures` no pipeline.** Dados, builder, validador e arquétipos desconhecem structures. Viola Levels §§1/5.
5. **Obstáculos sem conectividade.** `place_on_lane/off_lane` espalha pontos com anti-sobreposição (`OVERLAP_MARGIN 8 px`), ou seja, **proíbe** o contato que Levels exige. Não há grupos, paredes, torres ou vigas. Viola Levels §§5–6.
6. **Sem desenho intencional.** O "layout" é efeito colateral de pontos aleatórios + filtro do solver. Fases tendem a tiro direto com poeira ao redor. Viola Levels §§8/10.
7. **Mecânicas sem função.** Vidro/pedra/metal entram por cota, não como barreira quebrável, estrutura desgastável ou espelho com papel no caminho do disparo. Viola Levels §7.
8. **Solver como desenhista.** Hoje a aceitação é "o solver achou uma solução", mesmo que a composição seja trivial ou informe. Isso inverte a hierarquia correta (composição → validação → jogabilidade).
9. **Validador cego ao estrutural.** Passa fases com canhão flutuante, obstáculo isolado/flutuante e composição trivial, desde que não se sobreponham. Viola a exigência de validação de Levels.
10. **Escalas desalinhadas dos guides.** Guides usam grade de 100 px com peças encostadas; o gerador usa as mesmas escalas sem grade — as peças nunca se alinham.

Nota sobre a revisão anterior deste plano (para não repetir o erro): a primeira versão propunha 5 layouts fechados (`twin_towers`, `high_perch`, …), rampa/escada genérica única, regra "vão > 8 px → inserir Structure" e cotas rígidas (≥10/≥4, 80%). Essas decisões transformavam regras de design em heurísticas mecânicas — exatamente o que esta revisão elimina (ver §§ Estratégia/Validação/Critérios).

---

# Regras que Devem ser Atendidas

Mapeamento `docs/Levels.md` → requisito técnico. Onde `Levels.md` não fixa número, **nenhum número rígido é criado**; limites técnicos (orçamento, tolerâncias de contato, faixas de segurança) são marcados como `[TÉCNICO]` e justificados separadamente.

| # | Regra (Levels.md) | Requisito técnico |
|---|---|---|
| R1 | Fase tem `Floor + Cannon + Target + Obstacles + Structures (quando necessárias)` (§1) | `LevelDefinition` passa a carregar `floors`, `structures` e intenção (`composition`: papéis, grupos, âncoras — ver § Arquitetura). `LevelBuilder` instancia os grupos. Validador exige presença coerente: structures são exigidas **quando a composição declara uma conexão que precisa delas**, não por contagem fixa. |
| R2 | `Floor` cobre todo o piso (§2) | A composição sempre inclui a faixa base (`x = 50..1250` em `y = 670`, mesma grade dos guides) **mais** o relevo que o desenho exigir. Validador reprova vão na faixa base. `[TÉCNICO]` faixa/passo são herdados dos guides, não regra de design. |
| R3 | `Floor` encosta na base do `Cannon`; canhão nunca flutuante (§§2–3) | A composição declara o apoio do canhão (plataforma, degrau, coluna — ver § Estratégia); o topo do apoio toca o pé do canhão. Validação: contato geométrico com tolerância pequena `[TÉCNICO, calibrar ~4–8 px]` usando `CANNON_FOOT_OFFSET` medido na cena. |
| R4 | `Cannon` sempre à esquerda, altura qualquer definida pelo desenho (§3) | Posição do canhão é **decisão da composição** dentro da zona esquerda (lado esquerdo da tela; faixa exata como guarda `[TÉCNICO]` herdada do validador atual + guides, ex. `x` na casa das centenas baixas). Altura varia por desenho (baixo, meia-altura, alto). A grade de 100 px é **auxílio de construção**, não lei universal (ver § Estratégia). |
| R5 | `Floor` sobe até canhão elevado e retorna ao plano (§2) | A **forma** da subida/retorno pertence ao desenho (degraus, patamares, coluna, plataforma ligada ao piso — ver § Estratégia). O validador só verifica: (a) existe caminho de tiles do plano até o apoio; (b) o plano base continua sem vãos. Nenhum formato único obrigatório. |
| R6 | `Target` normalmente à direita, qualquer altura, rotacionado quando compõe (§4) | Posição e rotação do alvo são **decisões da composição** com função declarada (ex.: deitado para fechar tiro rasteiro, inclinado dentro de fortaleza para exigir ricochete/queda). `TargetDefinition` ganha `rotation_degrees`. Exceção "fora da direita" só com função explícita de desafio especial registrada na composição. Sem sorteio cego de ângulos. |
| R7 | Todo obstáculo conectado ao `Floor` direta/indiretamente; conectados entre si; sem flutuação (§5) | Modelo de **grafo de contato** (nós = floors + obstacles + structures; aresta = contato físico dentro de tolerância `[TÉCNICO]`). Validador exige: todo obstáculo alcança o floor por BFS; nenhum componente de 1 nó isolado. Estruturas declaradas como uma ou mais construções ancoradas (ver decisão D4). |
| R8 | Conexão via `Structures` quando necessário (§§1/5) | `Structures` são **elementos da composição** com papel declarado (`beam` liga A–B; `support` leva carga ao floor). A composição decide onde há viga/coluna; a validação verifica se cada conexão declarada existe geometricamente e se não há peça flutuante. **Proibido "preenchimento automático de vãos"**: nenhum corretor insere structure para salvar layout ruim — layout inválido é descartado. |
| R9 | Número considerável; sem aleatório sem propósito, repetição, vazios, isolados; construções reconhecíveis (§6) | "Considerável" é lido como **construção significativa**: grupos com função, densidade sem vazios injustificados, peças com papel. Sem cota rígida universal. Guardas `[TÉCNICO]` contra degeneração (ex.: rejeitar composições com 0–2 peças ou com área construída irrisória) devem ser calibrados na implementação e documentados como técnicos, não como "a regra dos N obstáculos". Ver § Validação. |
| R10 | Quebrar / desgastar / ricochetear com função (§7) | Material escolhido **por situação de jogo** declarada na composição (ver § Estratégia): barreira quebrável (vidro), estrutura desgastável (pedra), espelho/caminho de ricochete (metal). Validador + solver verificam a função (ver §§ Validação/Algoritmo). Sem cotas cegas por material fora das bandas de progressão já existentes. |
| R11 | Fase como composição única (§8) | Pipeline composition-first: uma `Composition` completa (canhão, floor, alvo, grupos, structures, materiais, funções) é gerada **antes** de qualquer instanciação; RNG varia **dentro** da composição, nunca cria a composição por soma de pontos livres. |
| R12 | Guides como referência, não cópia (§9) | Guides viram **vocabulário de padrões combináveis** (ver § Análise dos Guides), não templates. Regressão: nenhuma fase gera os AABBs exatos dos guides. |
| R13 | Construção intencional (§10) | Critério operacional: todo elemento carrega `group + role + anchor + mechanic_function` (ex.: grupo `fortress`, papel `mirror`, âncora `beam_2`, função `ricochet`). Peça sem papel não é "preenchimento" — ou ganha função na composição ou não existe. |

---

# Análise dos Guides

Releitura dos guides não como "duas fases para copiar", mas como **vocabulário de construção**. Medidas em coordenadas de mundo.

## Guide1 — canhão em plataforma baixa; torres + ponte + telhado

- `Cannon (150, 487) scale 0.3` sobre plataforma `Floor (150,570)+(250,570)`; base `50..1250 @670`.
- `Target (1198, 590) rotation 90°`: deitado, fechando tiro rasteiro, pedindo arco por cima.
- Torres de metal/pedra com passo ≈ lado da peça (contato direto); pedra-ponte entre torres; vigas `0.15` horizontais ligando topos; fileira superior de vigas sustentando telhado misto (metal + pedra + vidro 0.1 como miolo).
- Leitura de intenção: a **ponte** conecta, o **telhado** coroa, o **miolo de vidro** é o ponto fraco opcional, as **torres de metal** fecham o tiro baixo.

## Guide2 — canhão em coluna alta; corredor/telhado + fortaleza em U

- `Cannon (153, 80) scale 0.3` no topo de coluna `x=151, y=164..670` + patamar `150/250 @570`. A coluna **é** o desenho (anteparo à esquerda + verticalidade).
- `Target (908, 436) rotation ~145°`: inclinado dentro de construção, pedindo ricochete ou queda — rotação arbitrária com função, não "um dos N ângulos".
- Telhado-corredor contínuo `y≈170` (`x 255..1223`) alternando metal/vidro/pedra sobre vigas; coluna de structures `x=434` levando carga ao floor; fortaleza em U à direita com boca para o canhão.
- Leitura de intenção: o **corredor** organiza o espaço, a **coluna** sustenta, o **U** protege o alvo e orienta a entrada do disparo.

## Princípios generalizáveis → componentes reutilizáveis do gerador

A implementação deve transformar estas observações em **peças de vocabulário** (cada uma parametrizável), nunca em fases-modelo:

```text
Floor (forma do terreno — decidida pelo desenho)
 ├── Base (faixa contínua cobrindo o piso — sempre presente)
 ├── Platform (patamar que sustenta canhão, alvo ou grupo)
 ├── Steps (degraus de subida/descida com ritmo variável, não escada única)
 ├── Column (pilha vertical portante — também é anteparo/moldura)
 └── Notch / Pit-wall (degrau alto tipo Guide1/Guide2, elevação em L)

Structure (elemento de ligação — parte do desenho)
 ├── Beam (viga entre dois obstáculos/grupos — horizontal nos guides)
 └── Support (coluna/pé que leva carga ao Floor ou a outro elemento)

Obstacle composition (grupos — a unidade real de desenho)
 ├── Wall (fiada que barra ou conduz)
 ├── Tower (pilha vertical)
 ├── Bridge (peça(s) ligando torres/paredes — ex. pedra-ponte)
 ├── Roof (coroamento sobre vigas, misto por banda)
 ├── Fortress / Bunker (U ou cerco parcial com boca orientada)
 ├── Corridor (telhado + apoios organizando um eixo vazio com função)
 └── Gate (parede sobre o caminho do disparo com junta funcional)

Mechanic situations (função — o que o grupo FAZ no jogo)
 ├── Breakable barrier (vidro como tampa/junta que abre caminho)
 ├── Wear structure (pedra exigindo 2º impacto / gestão de munição)
 └── Ricochet feature (metal posicionado como espelho, funil ou bloqueio)

Cannon placements (intenções, não níveis fixos)
 ├── Ground (integrado ao plano)
 ├── Platform (patamar elevado com subida + retorno pelo desenho)
 └── Perch (coluna/torre alta — verticalidade como desafio)

Target placements (intenções)
 ├── Foot / Between-towers (baixo, entre construções, deitado)
 ├── Inside-fortress (protegido, boca orientada, inclinado)
 └── High / Exposed (alto, exigindo arco cheio ou ricochete)
```

Regras de combinação (exemplos, não lista fechada): `Tower + Bridge`, `Wall + Gate`, `Roof + Breakable barrier`, `Fortress + Ricochet feature`, `Platform + Steps`, `Perch + Corridor`. A variedade nasce da **combinação**, não da escolha de um template.

Tudo usa as medidas reais: tile floor 0.2 = 100×100; pedra 0.2 = 100×100; metal 0.2 ≈ 110×110; vidro 0.1 ≈ 95×93; structures 0.15 (medir `structure.png` na implementação); grade de 100 px com snap 50 px como **auxílio**, não como lei.

---

# Estratégia de Geração

## 1. Composição antes de objetos

Cada fase nasce como uma **`Composition`**: um documento de intenção completo antes de existir qualquer Node. Conteúdo mínimo:

- `cannon`: posição, escala e **intenção** (`ground | platform | perch`) + apoio declarado (quais tiles/grupos sustentam).
- `floor_shape`: perfil do terreno (base + relevo do desenho: degraus, patamares, coluna, L — ver §2) como lista de tiles intencionais.
- `target`: posição, rotação e **função** (`foot | inside-fortress | high…`) + por que a rotação existe.
- `groups`: 1–4 grupos de obstáculos, cada um com **tipo** (`wall | tower | bridge | roof | fortress | corridor | gate`), peças, materiais e **função mecânica** (`breakable | wear | ricochet | frame`).
- `structures`: cada viga/coluna com **papel** (`beam A–B | support → floor`) e extremidades declaradas.
- `shot_intent`: intenção de desafio (ex.: "arco por cima do telhado", "quebrar junta e entrar pela boca", "ricochete no espelho") — guia a escolha dos grupos, **não** é traçado pelo solver.

RNG só varia **dentro** de uma composição (dimensões, lados, materiais da banda, rotações funcionais). RNG nunca posiciona peças livres.

## 2. Floor como desenho (não "plano + escada genérica")

O `Floor` tem requisitos fixos (base coberta, apoio do canhão, subida + retorno), mas **forma livre**. O compositor escolhe um perfil por fase, por exemplo:

```text
Perfil A — patamar em L (Guide1):      Perfil B — coluna (Guide2):
___________                             ____
		  |                              |
		  |____                           |____

Perfil C — degraus suaves:              Perfil D — plataforma ligada:
____                                     ___________
   \___                               ___|         |___
	   \___                          |_________________|
```

Primitivas à disposição do compositor (executadas por um ajudante `FloorShapes`, que **executa** o que a composição decidiu — não decide sozinho): `base`, `platform`, `steps(início, fim, ritmo)`, `column`, `notch`. Ritmo, largura, lado da subida e lado do retorno variam por desenho. O validador verifica requisitos (R2/R3/R5), nunca impõe o perfil.

## 3. Structures como desenho (não "tapa-vão")

Cada structure nasce com papel declarado:

```text
Obstacle ─ Beam ─ Obstacle        Obstacle
							   |
							Support
							   |
							Support
							   |
							 Floor
```

Um ajudante `StructureShapes` posiciona a peça que a composição pediu (viga entre A–B, coluna até o floor). Se a composição declara uma ligação, a peça existe desde o nascimento — **nenhum corretor posterior insere structures**. A validação confere: cada `beam` toca as duas extremidades; cada `support` chega ao destino; nada flutua.

## 4. Mecânicas como situações de jogo (não "material = X")

O compositor escolhe materiais **pela situação que quer criar**:

- **Quebrar (vidro):** barreira, tampa, junta ou miolo que o disparo **abre**. Situações: gate com junta de vidro no caminho; telhado com miolo quebrável permitindo queda vertical; tampa sobre a boca da fortaleza. A composição declara `breakable_at: <grupo/peça>`; a jogabilidade esperada é "destruir para passar", verificada pelo solver (peça destruída no caminho vencedor).
- **Desgastar (pedra):** estrutura que **cobra o 2º impacto**. Situações: ponte de pedra que precisa de dois tiros; parede com núcleo de pedra + gestão de munição (`ammo ≥ 2`); camada externa que racha no 1º tiro e cai no 2º. A composição declara `wear_at`; o solver confirma custo extra de tiro.
- **Ricochetear (metal):** geometria que **dobra o caminho**. Situações: espelho deslocado fora da reta; funil conduzindo à boca; bloqueio total da reta direta exigindo reflexão; coluna que devolve o disparo para o alvo. A composição declara `ricochet_feature`; o solver confirma reflexão(ões) no caminho vencedor.

Bandas de dificuldade continuam dizendo **quais situações** podem aparecer (início: só quebra leve; meio: +desgaste; avançado: +ricochete), nunca quantidades cegas.

## 5. Cannon e Target como decisões compositivas

- **Cannon:** sempre à esquerda, altura e apoio definidos pela intenção (`ground | platform | perch`). A grade auxilia o assentamento (peças de 100 px empilham bem em níveis cheios), mas o layout pode assentar em meio-nível compatível com os guides (ex. Guide1 `487` sobre plataforma `570`) desde que o contato seja exato. Proibida a regra universal `y = 670 − k·100`.
- **Target:** normalmente à direita, posição/altura/rotação definidas pela função no desenho. A rotação é **justificada** (deitar para fechar rasteiro, inclinar para orientar entrada, expor para arco). Proibido sorteio cego entre ângulos.

## 6. O que NÃO muda

- Determinismo por `RandomNumberGenerator` com seed explícita; bump de `GENERATOR_VERSION` quando o algoritmo mudar.
- Orçamento 250–300 ms `[TÉCNICO]`, tentativas limitadas com fallback aberto como rede final.
- `Game.tscn`: HUD, câmera, inputs, popups intactos. `Level` continua o contêiner; `Cannon` continua nó da cena (só posicionado/escalado pela composição).

---

# Arquitetura Proposta

Separação explícita **Composição × Validação × Instanciação**. Nada que valida desenha; nada que instancia decide.

## Camada 1 — Composição (decide TUDO do desenho)

| Componente | Tipo | Responsabilidade |
|---|---|---|
| `Composition` (novo; `RefCounted` ou `Resource` puro-dados) | Dados de intenção | Documento da fase antes dos Nodes: `cannon` + `floor_shape` + `target` + `groups[]` + `structures[]` + `shot_intent`, cada elemento com `group + role + anchor + mechanic_function`. É o que o RNG constrói e o validador lê. Pode ser serializada para debug. |
| `PatternLibrary` (novo) | Vocabulário | Biblioteca dos padrões do § Análise (floor profiles, grupos, cannon/target placements, mechanic situations). Expõe peças parametrizáveis, **não fases prontas**. Substitui a ideia de "5 layouts fechados". |
| `CompositionBuilder` / `Composer` (novo) | Geração | Monta uma `Composition` combinando padrões: escolhe intenção do canhão → perfil do floor → função do alvo → 1–4 grupos → structures com papel → materiais por situação/banda. Único lugar onde RNG toca no desenho. Substitui `LayoutCatalog`/arquétipos fechados. |
| `FloorShapes` (novo, ajudante) | Execução | Primitivas `base / platform / steps / column / notch`: convertem o perfil decidido em tiles. Sem RNG próprio, sem decisão. |
| `StructureShapes` (novo, ajudante) | Execução | `beam(A,B) / support(P→destino)`: convertem papéis em peças. Sem RNG próprio, sem "tapa-vão". |

## Camada 2 — Validação (só verifica; nunca conserta)

| Componente | Tipo | Responsabilidade |
|---|---|---|
| `LevelValidator` (alterar: +`validate_structure`) | Validação | Camada de segurança geométrica: limites, contato floor–canhão, base sem vãos, subida+retorno existentes, grafo de contato (todo obstáculo alcança o floor; sem isolados/flutuantes), structures tocam as extremidades declaradas, coerência física (dentro de `play_bounds`, sem sobreposição indevida), construção significativa (anti-degeneração). **Reprova sem corrigir.** |
| `DifficultyConfig` / `DifficultyTable` (alterar: mínimo) | Regras de progressão | Dizem quais **situações** cada banda permite (quebra → desgaste → ricochete) e guardas técnicos (orçamento, munição 1–4 herdada do jogo). Sem cotas rígidas de contagem por material fora do que já existe. |
| Solver (`FastLevelGenerator.solve_direct` no caminho quente; `LevelSolver` físico offline) | Validação de jogabilidade | Último portão: confirma que a composição é jogável **com a assinatura esperada** (quebra/desgaste/ricochete declarados aparecem no caminho vencedor; tiros ≤ munição). Não reposiciona nada; só aprova/rejeita. |

## Camada 3 — Dados e instanciação (só carregam/concretizam)

| Componente | Ação | Motivo |
|---|---|---|
| `FloorDefinition` (criar) | Tile de floor serializável | Floor vira dado da fase. |
| `StructureDefinition` (criar) | Viga/coluna serializável + papel | Structures viram dado da fase. |
| `TargetDefinition` (alterar) | +`rotation_degrees` + serialização | Rotação funcional do alvo. |
| `LevelDefinition` (alterar) | +`floors`, `structures`, `composition_id/tags` (linhagem, **não** template fixo), `cannon_scale`; bump versão → 2; compat v1 | Fase completa + rastreabilidade do desenho. O campo `layout_id` da versão anterior é substituído por tags compositivas (ex.: `perch+corridor+fortress`) para não congelar templates. |
| `MaterialRules` (alterar: mínimo) | +`structure_size()`, `floor_size()` | AABBs de floor/structure no validador. Sem mudar regras de materiais. |
| `LevelBuilder` (alterar) | Instancia `floors`, `structures`, obstáculos, target **com rotação**; expõe pose do canhão | Concretiza a composição aprovada, sem decidir nada. |
| `screens/game.gd` (alterar: mínimo) | Aplica `cannon.position/scale` da composição | Canhão em altura variável. |
| `components/level/archetypes/*.gd` (6 legados) | Remover/arquivar ao fim (manter `open_shot` como referência simples até o compositor cobrir a banda inicial) | Evita dois sistemas concorrentes. |
| `components/level/tests/*` | Estender (composição, validador, builder, generator, benchmark) | Cobrir intenção, erros estruturais e orçamento. |
| `screens/game.tscn`, HUD, câmera, controles, `home.tscn`, `guide/` | **Não tocar** | Fora do escopo / referência imutável. |

## Decisões abertas (para a implementação)

- **D1. Grade como auxílio.** Snap 50 px + peças de ~100 px (medidas reais no Apêndice). Posições livres são permitidas se o contato for exato e compatível com os guides.
- **D2. Ponto de apoio do canhão.** Medir `cannon.tscn` (offset base→pé em `scale 0.2/0.3`) e fixar `CANNON_FOOT_OFFSET`; só o validador usa.
- **D3. `Structure` sem colisão (v1).** Recomendado: manter `Node2D` + sprite como nos guides, com contato geométrico validado por AABB; não virar `StaticBody2D` agora (mudaria rebotes e exigiria recalibragem do solver). Registrar a escolha no código.
- **D4. Uma ou mais construções.** Exigir grafo conexo ao floor por padrão; admitir 2+ construções se **cada uma** estiver ancorada no floor e a composição declarar a intenção (ex.: canhão em coluna + fortaleza separada). Sem componentes flutuantes em nenhum caso.
- **D5. Campo de linhagem.** Usar `composition_tags` (ex.: `platform+gate+roof`) em vez de `allowed_archetypes`/`layout_id` rígidos; migrar `DifficultyConfig` para "situações permitidas por banda" com compatibilidade dos testes.

---

# Algoritmo de Geração

```text
1. rng = RNG(hash(seed : v2 : level_number)); cfg = situações permitidas na banda
2. repetir até MAX_ATTEMPTS [TÉCNICO] ou estourar 250 ms [TÉCNICO]:
   a. Composer monta Composition combinando padrões:
	  a1. intenção do canhão (ground | platform | perch) + apoio declarado
	  a2. perfil do floor (base + relevo do desenho) via FloorShapes
	  a3. função do alvo (posição + rotação justificada)
	  a4. 1–4 grupos (wall | tower | bridge | roof | fortress | corridor | gate)
		  com materiais da situação (breakable | wear | ricochet | frame)
	  a5. structures com papel (beam A–B | support → floor) via StructureShapes
	  a6. shot_intent registrado (ex.: "quebrar junta e entrar pela boca")
   b. LevelValidator.validate(def) — limites, muzzle, sobreposição indevida (regras atuais)
   c. LevelValidator.validate_structure(def) — NOVO: requisitos Levels (ver § Validação)
   d. validate_config mínima — só situações/munição da banda, sem cotas cegas
   e. solver (solve_direct; amostragem física offline) — confirma jogabilidade
	  COM a assinatura declarada (quebra/desgaste/ricochete aparecem; tiros ≤ munição)
   f. score em banda (faixa larga [TÉCNICO]; corta extremos, não desenha) → RETORNA
3. fallback: seeds curadas (mesmo pipeline) → ultimate aberto legado (rede final)
```

Exemplo ilustrativo (um entre muitos — **não** um template):

```text
canhão platform à esquerda + floor em L + alvo deitado entre construções
+ torre esquerda + ponte de pedra + viga declarada + telhado com miolo de vidro
→ valida grafo → solver confirma "arco por cima, opcional quebrar miolo" → instancia
```

Outro exemplo com o mesmo vocabulário, desenho diferente: canhão `perch` em coluna + corredor de vigas + fortaleza em U com boca orientada + espelho de ricochete — a composição varia em nº de grupos, altura, largura, simetria, floor, materiais e caminho do projétil.

`LevelBuilder.build()` instancia na ordem: floors → structures → obstáculos → target (com rotação) → `game.gd` aplica a pose do canhão. `clear()` remove os grupos via `level_spawned`.

---

# Validação

`LevelValidator.validate_structure(def)` — camada de segurança **geométrica, sem física**, executada antes do solver. Pergunta única: *"a composição criada é válida?"*. Se não, **rejeita e gera outra** — nunca conserta.

| Código | Detecta (intenção correspondente entre parênteses) |
|---|---|
| `FLOOR_GAP` | vão na faixa base do piso |
| `CANNON_FLOATING` | apoio declarado não toca o pé do canhão (tolerância `[TÉCNICO]`) |
| `CANNON_SIDE` | canhão fora do lado esquerdo |
| `FLOOR_NO_ASCENT` | canhão elevado sem caminho de tiles até o apoio |
| `FLOOR_NO_RETURN` | relevo sem retorno ao plano base (plano descontínuo) |
| `OBSTACLE_FLOATING` | obstáculo sem contato com floor/obstáculo/structure |
| `OBSTACLE_ISOLATED` | grupo de 1 peça sem arestas (construção exige grupo) |
| `STRUCTURE_UNGROUNDED` | `beam` sem tocar as duas extremidades declaradas, ou `support` sem chegar ao destino |
| `TARGET_OUT_OF_ROLE` | alvo fora da zona direita sem função de exceção declarada; rotação sem função |
| `TRIVIAL_COMPOSITION` | construção insignificante `[TÉCNICO, calibrar na implementação como guarda anti-degeneração — ex.: nº irrisório de peças ou área construída desprezível]` — documentado como técnico, não como "regra dos N" |
| `MECHANIC_WITHOUT_ROLE` | banda/situação declara quebra/desgaste/ricochete mas nenhuma peça cumpre a função no caminho vencedor (checagem conjunta com o solver) |
| `OUT_OF_BOUNDS` (reuso) | qualquer peça fora de `play_bounds` |

Grafo de contato: nós = floors + obstacles + structures (AABBs via `MaterialRules`: `base_size*scale`, 90° troca eixos; target fora do grafo). Aresta se AABBs dilatados (tolerância `[TÉCNICO, ~6 px]`) se intersectam; viga conta como aresta entre os vizinhos declarados **e** deve tocar ambos. BFS a partir dos tiles floor: **todo obstáculo alcançável** (R7). Só matemática 2D — custo em ms.

Testes: fixtures de composições válidas no espírito dos guides (sem copiá-los) + fixture mínima para cada erro acima + regressão anti-cópia (nenhuma fase gera os AABBs exatos de Guide1/Guide2). Nenhum teste deve exigir contagem exata de peças como "prova de qualidade".

---

# Variedade dos Layouts

A variedade nasce da **combinação de padrões**, nunca da escolha de um template + jitter:

- **Eixos de variação** (todos decididos pela composição): nº de grupos (1–4) e seus tipos; altura/largura/simetria; posição/altura do canhão e perfil do floor; posição/altura/rotação do alvo; nº e papéis das structures; materiais por situação; caminho do projétil (arco, queda, quebra, desgaste, ricochete simples/duplo); barreiras e pontos fracos.
- **Exemplo de espaço combinatório**: 3 intenções de canhão × 4+ perfis de floor × 3 funções de alvo × 7 tipos de grupo × 3 situações mecânicas — mesmo com parâmetros modestos, sementes vizinhas produzem desenhos estruturalmente distintos (torre vs. fortaleza vs. corredor), não "a mesma fase 20 px ao lado".
- **Anti-repetição**: linhagem `composition_tags` + hash dos parâmetros no `log`; o compositor evita repetir a mesma assinatura da fase anterior quando o RNG permitir, sem quebrar determinismo (sequência continua função de `seed:fase`).
- **Anti-trivialidade**: `TRIVIAL_COMPOSITION` + `MECHANIC_WITHOUT_ROLE` rejeitam fase insignificante ou com mecânica decorativa; vazios só passam com função declarada (ex.: pátio de queda do disparo).
- **Anti-solução-reta-indesejada**: se a composição declara bloqueio/quebra/desgaste/ricochete, o caminho vencedor precisa exibir a assinatura (peça destruída, custo extra, reflexão); senão, rejeita — o solver **atesta**, não desenha.

---

# Alterações Necessárias

| Arquivo | Ação | Motivo |
|---|---|---|
| `components/level/composition.gd` | **Criar** (intenção: cannon, floor_shape, target, groups, structures, shot_intent, papéis/âncoras/funções) | Coração do composition-first; o que se valida e instancia. |
| `components/level/pattern_library.gd` (+ `patterns/` por família: floor, grupos, cannon/target placements, mechanic situations) | **Criar** | Vocabulário combinável abstraído dos guides; sem fases-modelo. |
| `components/level/composition_builder.gd` | **Criar** (monta `Composition` com RNG; único decisor do desenho) | Combina padrões em desenhos diferentes. |
| `components/level/floor_shapes.gd` | **Criar** (primitivas `base/platform/steps/column/notch`, sem RNG) | Executa o perfil de floor decidido. |
| `components/level/structure_shapes.gd` | **Criar** (`beam/support` por papel declarado, sem RNG, sem tapa-vão) | Executa as structures decididas. |
| `components/level/floor_definition.gd` | **Criar** (`Resource` serializável) | Floor vira dado da fase. |
| `components/level/structure_definition.gd` | **Criar** (+ papel/extremidades, serializável) | Structures viram dado da fase. |
| `components/level/target_definition.gd` | **Modificar** (+`rotation_degrees`, serialização) | Rotação funcional do alvo. |
| `components/level/level_definition.gd` | **Modificar** (+`floors`, `structures`, `composition_tags`, `cannon_scale`; bump → 2; compat v1) | Fase completa + linhagem compositiva. |
| `components/level/level_validator.gd` | **Modificar** (+`validate_structure`, `floor_aabb`, `structure_aabb`, códigos do § Validação) | Camada de segurança Levels; reprova sem corrigir. |
| `components/level/material_rules.gd` | **Modificar** (+`structure_size()`, `floor_size()`) | AABBs no validador; resto intacto. |
| `components/level/fast_level_generator.gd` | **Modificar** (orquestra composer → validadores → solver; sem lógica de desenho) | Pipeline composition-first; solver só no fim. |
| `components/level/level_builder.gd` | **Modificar** (instancia floors/structures/target com rotação; expõe pose do canhão) | Concretiza composição aprovada. |
| `components/level/difficulty_table.gd` + `difficulty_config.gd` | **Modificar** (mínimo: situações permitidas por banda; sem cotas cegas) | Progressão quebra → desgaste → ricochete. |
| `screens/game.gd` | **Modificar** (mínimo: aplicar `cannon.position/scale`) | Canhão em altura variável. |
| `components/level/archetypes/*.gd` (6 legados) | **Remover/arquivar ao fim** | Evita sistema concorrente de pontos aleatórios. |
| `components/level/tests/*` | **Estender** | Cobrir composição, validação, jogabilidade, determinismo, orçamento. |
| `screens/game.tscn`, HUD, câmera, controles, `home.tscn`, `guide/` | **Não tocar** | Fora do escopo / referência imutável. |

---

# Ordem de Implementação

Etapas pequenas, cada uma verificável (concluir só com teste verde; nenhuma etapa "conserta" layout — só constrói, verifica ou instancia):

1. **Dados de intenção.** Criar `FloorDefinition` + `StructureDefinition` (com papel); estender `TargetDefinition` (rotação) e `LevelDefinition` (floors/structures/tags/cannon_scale, v2, compat v1); esboçar `Composition` (papéis/âncoras/funções). Verificação: round-trip `to_dict/from_dict` v1+v2.
2. **Geometria de referência.** `MaterialRules.structure_size/floor_size` (medir sprites) + `CANNON_FOOT_OFFSET` (medir `cannon.tscn` 0.2/0.3). Verificação: AABBs conferem com peças dos guides (tolerância 2 px).
3. **Validador como camada de segurança.** `validate_structure()` + códigos do § Validação, desligado do gerador. Verificação: composições no espírito dos guides passam; cada erro tem fixture mínima que o dispara; inválido é rejeitado, nunca corrigido.
4. **Ajudantes de execução.** `FloorShapes` + `StructureShapes` (funções puras, sem RNG). Verificação: cada primitiva produz exatamente as peças pedidas com medidas exatas.
5. **Vocabulário + compositor mínimo.** `PatternLibrary` (primeiros padrões: patamar, degraus, coluna; torre, parede, gate; barreira quebrável) + `CompositionBuilder` gerando composições completas com 1–2 grupos. Verificação: 50 seeds, 100% passam em `validate + validate_structure` sem tapa-vão.
6. **Integração composition-first.** `FastLevelGenerator` orquestra composer → validadores → solver (solver só atesta jogabilidade + assinatura mecânica). Verificação: benchmark ≤ 250 ms `[TÉCNICO]`; fallback ≤ taxa atual.
7. **Instanciação.** `LevelBuilder` + `game.gd` (pose do canhão). Verificação: nós/posições/rotação/grupos conferem; `Game.tscn` jogável com fase elevada.
8. **Vocabulário completo.** Restante dos padrões (fortaleza, corredor, telhado, espelho/funil de ricochete, estrutura desgastável, `perch`, alvo em fortaleza/alto). Verificação: sementes vizinhas geram combinações estruturalmente distintas (tags diferentes).
9. **Calibragem e regressão.** Amostragem com solver físico offline; anti-cópia dos guides; atualizar seeds de fallback se preciso; calibrar guardas `[TÉCNICO]` (tolerâncias, anti-degeneração, banda de score larga). Verificação: suíte verde + relatório de jogabilidade.
10. **Limpeza.** Arquivar arquétipos legados; bump final de versão se necessário; atualizar comentários que citam o plano. Verificação: suíte completa verde, sem referências órfãs.

---

# Critérios de Aceitação

Verificação principal (qualitativa e estrutural; sem métricas que o gerador possa "decorar"):

1. **Composição intencional.** Amostra de fases (ex.: 20 seeds × fases 1/5/12/18) lida como construção deliberada: grupos reconhecíveis (torre, parede, ponte, telhado, fortaleza, corredor, gate) com papéis, sem poeira aleatória nem vazios injustificados.
2. **Cannon integrado ao Floor.** 100% da amostra: canhão no lado esquerdo, apoiado com contato (sem `CANNON_FLOATING`), apoio coerente com a intenção (`ground | platform | perch`).
3. **Floor cobre o piso.** 100% da amostra: faixa base contínua sem vãos.
4. **Floor chega ao Cannon elevado.** 100% das fases com canhão elevado: caminho de tiles do plano até o apoio + retorno ao plano (sem `FLOOR_NO_ASCENT`/`FLOOR_NO_RETURN`), na forma que o desenho escolheu (degraus, coluna, L… — nunca cobrado um perfil único).
5. **Target integrado ao desenho.** Alvo na zona direita por padrão (exceção só com função declarada); rotação sempre justificada pela função (fechar rasteiro, orientar entrada, pedir arco/ricochete); sem sorteio cego.
6. **Obstacles sem flutuação.** 100% da amostra: `validate_structure()["ok"]`, todo obstáculo alcança o floor por BFS, sem isolados.
7. **Structures conectam de verdade.** Cada `beam` toca as extremidades declaradas; cada `support` chega ao destino; structures existem porque a construção as pediu (papel legível), nunca como tapa-vão.
8. **Mecânicas com função.** Fases que prometem quebra/desgaste/ricochete exibem a assinatura no caminho vencedor (barreira destruída / custo extra de tiro com `ammo ≥ 2` / reflexão com papel no trajeto). Material decorativo sem função é rejeitado pela leitura da composição.
9. **Desenhos estruturalmente diferentes.** Sementes vizinhas produzem combinações distintas (tags/grupos/floor/alvo diferentes); nenhuma fase reproduz os AABBs dos guides.
10. **Jogável.** Solver aprova 100% das fases entregues (caminho vencedor dentro da munição e das situações da banda).
11. **Determinística.** Mesma `(seed, fase)` → `to_dict()` idêntico.
12. **Compatível com `Game.tscn`.** HUD, câmera e controles inalterados; vitória/derrota via `target_hit`; defs v1 antigas ainda desserializam; geração dentro do orçamento `[TÉCNICO]` ~250–300 ms.
13. **Suíte verde.** Testes em `components/level/tests/` passam, incluindo composição, validação estrutural, anti-cópia e determinismo — sem testes que exijam contagens exatas como prova de qualidade.

---

## Apêndice — Medidas de referência (não reinventar)

- Viewport `1280×720` (`project.godot`); `play_bounds (0,0,1280,720)`; chão dos guides `y=670`, faixa `x=50..1250` passo 100, tile `100×100` @0.2.
- Metal 0.2 ≈ 110×110; pedra 0.2 = 100×100; vidro 0.1 ≈ 95×93; structure 0.15 = 72×67 (medido: `structure.png` 482×448); alvo colisor real ~23×95 @0.2 (polígono 114×474 — NÃO 80×80, que é aproximação só do validador).
- Canhão guides: `(150,487)@0.3` (Guide1, plataforma) e `(153,80)@0.3` (Guide2, coluna); pé do canhão = origem + 277px locais × escala (`Cannon.FOOT_DROP`, calibrado no Guide1).
- Solver analítico: Euler 60 Hz, `BULLET_RADIUS 10` (≈ bala 9.2px @0.2 no jogo), vidro destrói+atravessa `*=0.85`, pedra HP2 rebate / HP1 destrói+atravessa (multi-tiro com estado), metal reflexão exata por faces, `MAX_RICOCHETS 10`, kill `play_bounds+400`, alvo = AABB real + rotação + dilatação.

## Apêndice — Resoluções da implementação (etapas 1–10, branch `feature/level-generation-structure`)

Decisões abertas resolvidas: D1 grade como auxílio (snap 50, posições livres se o contato for exato); D2 `FOOT_DROP 277` medido; D3 structure segue sem colisão (AABB validado); D4 múltiplas construções admitidas se cada uma ancorada no floor; D5 `composition_tags` em vez de `layout_id` (sem templates rígidos).

Lições que mudaram o desenho no caminho (ler antes de estender o vocabulário):

- Pedra/metal NA LINHA do tiro baixo são veneno (rebatem): só vidro atravessa. Torres de pedra sobre a linha muralham o alvo — a fase 5 provou. Torre baixa só com canhão alto (linha passa por cima) ou fora da linha.
- Skip de tampa (quicar e cair no alvo) é fio-de-navalha sistemático: quina de 110px para alvo de 43px. Rejeitado; padrão "return" no lugar (parede à direita devolve no alvo, faces de 100px, alvo de 115px, retorno curto de 220px).
- Lean-to (muro + alvo baixo) não tem payoff: ou muralha ou exige queda-agulha. Rejeitado com a justificativa no histórico.
- Solver precisa ser ciente do mínimo de ricochetes (senão a direta sem rebote vence sempre) e medir folga (clearance ≥ 12px de faces reais) ainda na varredura; margem ±0.5° como portão final. Raspão + retorno longo = rejeitado.
- Clearance mede contra faces REAIS (dilatadas se sobrepõem em peças adjacentes) e exclui contato do passo + caixa do rebote anterior (o passo de saída começa em cima dela).

Limitações conhecidas (não mascaradas):

- Destroy da pedra tem race na física (`stone_obstacle.gd` relê `linear_velocity` após o rebote do motor; o re-apply de 2 frames nem sempre vence): o registro analítico correspondente pode falhar no replay (~7% amostrado nas 11–15). A fase continua vencível (o jogador mira livremente); corrigir é refatorar física — fora do escopo.
- Bandas 16+ (2+ ricochetes): compositor 0/24 no experimento de skip duplo; seguem legado + ultimate. Skip duplo é o próximo trabalho de vocabulário.
- `generator_test`/`generation_benchmark` (caminho legado, física real-time) são lentos por design (~1s/sim); CI deve tratá-los à parte.
- Seeds 1207 (fase 12) e 1508 (fase 15) do proof são curadas (1507 cai no race acima); `FALLBACK_SEEDS` segue a mesma filosofia.
