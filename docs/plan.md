# Plano de Refatoração — Geração e Execução de Fases

> Somente planejamento. Nenhuma implementação foi feita.

## 1. Diagnóstico atual

### 1.1 Como o sistema funciona hoje

- `LevelDefinition` (`components/level/level_definition.gd`) é o DTO puro da fase: `seed`, `level_number`, `ammo` (1..4), `cannon_position` (fixo `173,523`), `cannon_angle_min/max` (`-20/83`), `power_min/max` (`0.3/1.0`), `base_shot_speed` (`2000.0`), `play_bounds` (`Rect2(0,0,1280,720)`), `target: TargetDefinition` (80x80), `obstacles: Array[ObstacleDefinition]`, `solution: SolutionRecord`.
- `DifficultyTable` / `DifficultyConfig` traduzem `level_number` em cotas: `ammo`, `max_obstacles`, `glass/stone/metal_count`, `required_ricochets_min`, `allowed_archetypes`, `solver_angle_step/power_step` (hoje `10.0/0.35` em produção), banda de `score`.
- 6 arquétipos (`components/level/archetypes/`): `open_shot`, `glass_barrier`, `stone_gate`, `combo_order`, `blocked_direct`, `bunker`. Cada `place(def, rng, cfg)` sorteia alvo (`spot_target`: `x 950..1200, y 80..640`, exceto `bunker`: `x 950..1050, y 250..470`) e espalha obstáculos com `place_on_lane` / `place_off_lane`, `fits()` espelhando o validador.
- `LevelValidator` faz checagem geométrica barata (AABB `base_size*scale`, `CANNON_EXCLUSION=150`, `TARGET_EXCLUSION=100`, `OVERLAP_MARGIN=8`, `MIN_CANNON_TARGET_DIST=500`, `MUZZLE_CORRIDOR=(280,-60)`, alvo cercado por metal, rotação só `0/90`, escala `0.05..1.0`).
- `ProceduralLevelGenerator.generate(seed, level, parent)` tenta até `MAX_CANDIDATES=40` dentro de `TIME_BUDGET_MS=300`: `pick_archetype` → `place` → `validate` → `validate_config` → `LevelSolver.solve` → filtro `required_ricochets_min` → `DifficultyScorer.in_band` → anexa `solution`. Se falhar, tenta `FALLBACK_SEEDS` por banda e por fim `ultimate_fallback` (alvo `1000,326`, sem obstáculos, sem `solution`).
- `LevelSolver.solve` é BFS por profundidade até `def.ammo` (1..4) sobre grade `ângulo × potência`. Cada transição = `simulate_shot()` que instancia `simulation_world.tscn` + cenas reais dos obstáculos + `bullet.tscn`, roda `run_shot()` aguardando `physics_frame` por até `TIMEOUT_FRAMES=360` (6 s a 60 Hz), com términos `target/lost/returned/exited/stopped/timeout`. Conta ricochetes via `body_entered` em metal/pedra, `end_state` (HP pedra / vivo vidro), mais sonda de margem `±0.5°` (`2×total_shots` sims extras).
- `DifficultyScorer.score` mede dificuldade na solução (`3.0×shots + 2.0×ricochetes + 1.5×pedras + 1.0/margem + 2.0/raridade + 1.0×distância`).
- `LevelBuilder` instancia o que `LevelDefinition` manda em `world` (obstáculos via `MaterialRules.scene_for` + `target.tscn`), grupo `level_spawned`, `clear()` + 1 `physics_frame`. Não instancia chão, nem canhão, nem bala.
- `CannonController` (`components/cannon-controller/`) é hoje o jogo de fato: `load_level()` async gera + `builder.build` + posiciona `cannon` + controla `ammo_total/ammo_left`, `power_slider.power_changed → cannon.set_power`, `fire_button.pressed → shoot()`, vitória via `target.hit`, derrota após `END_DELAY=8s` sem balas com munição zerada, mira por drag (`rotate_cannon`), `StatusLabel`.
- `Game.tscn` (`screens/game.tscn`) é um `Control` sem script: `WorldArea` (esquerda, `offset_right=-200`) com `WorldBackground` + `World: Node2D` vazio, `ControlsArea` (faixa 200 px direita), `Divider`, `Hud` instanciado. Sem canhão, sem `Level`, sem chão, sem ligamento slider/botão/canhão, sem geração.
- `HUD` (`components/hud/hud.tscn`) é `Control` sem script (`hud.gd` não existe): `Info/Column` com `Level/Score/Ammo` (`"Fase: 0"`, `"Pontos: 0"`, `"Munição: 0"` estáticos) + `Controls` com `PowerSlider` + `FireButton` instanciados. Ninguém atualiza os labels.
- `Cannon` (`cannon.gd/tscn`): `min_angle=-20`, `max_angle=83`, `rotation_sensitivity=0.5`, `base_shot_speed` default `1000.0` (o `CannonController.tscn` sobrescreve para `2000.0`, igual ao `LevelDefinition`), `current_angle=45`, `current_power=1.0`, mira `BarrelPivot.rotation=-angle`, `muzzle_state_for()` (`PIVOT_OFFSET=(-2,-44)`, `MUZZLE_OFFSET=(267,-48)`), `shoot(power)` instancia `bullet_scene`, `apply_cannon_scale`, preview `TrajectoryLine` (só `0.35 s`, `max_distance=400`, 7 pontos).
- `PowerSlider` (`0.3..1.0`, `sensitivity=0.0012`, sinal `power_changed`) e `FireButton` (`TextureButton` sem script próprio) são burros: só emitem, quem liga é o controller.
- Obstáculos lidos do código (fonte da verdade em `material_rules.gd`): vidro 1 HP atravessável (`*=0.85`, `Area2D` filho, não rebate), pedra 2 HP (`bounce=1.0`, 1º hit racha+rebote motor, 2º hit atravessa `*=0.85` + `queue_free` após 2 frames), metal indestrutível (`bounce=1.0`, sem atenuação por código). Divergem do PRD RN-04 (pedra −30%, metal −5%) — vale o código.
- `Guide.tscn` (`guide/Guide.tscn`) é fase manual de referência, não usada em runtime: `World: Node2D` com `Obstacles` (vidro `0.1` em `1050,243`; muro metal `0.2` vertical `x≈1050` em `y 31/141/345/455/565`; 2 pedras `0.2` em `1161,465` e `1223,360`), `Ground` (13 `floor.tscn 0.2` cobrindo `x 50..1250, y 670` + plataforma `150,570` + `250,570`), `Target` em `1230,572`, `Cannon 0.3` em `150,487`.
- `Floor` (`floor.tscn`): `StaticBody2D` 500x500 com sprites; em `0.2` ≈ 100x100 px por peça.

### 1.2 Por que a geração leva minutos

Medido no próprio repo (`generation_benchmark.gd`, desktop headless 2026-09-25): `~640–745 ms/sim` em física tempo-real.

- Cada `simulate_shot` espera `physics_frame` reais (até 360 frames) — não é CPU, é espera de engine. `TIME_BUDGET_MS=300` só é checado *entre* candidatos, nunca aborta um `solve()` já em curso.
- Grade grossa atual (`10°×0.35` ≈ 11 ângulos × 3 potências ≈ 33 sims por profundidade) × BFS até `ammo` (até 4 níveis, `FRONTIER_CAP=24`) × `MAX_SIMULATIONS=800` + sonda de margem. Grade fina original (`2.0×0.1` ≈ 52×9 ≈ 416 sims/candidato) daria `416 × 640 ms ≈ 4–5 min por candidato` (extrapolação no próprio benchmark).
- Até 40 candidatos + `_try_fallback_seeds` (3 candidatos × N seeds) + cada `run_shot` instanciando/destruindo `SimulationWorld` + cenas reais + tweens + shards desligados mas com `await physics_frame` — explosão combinatória de tentativa-e-erro com física real no caminho crítico.
- Conclusão: o gargalo não é o `place()` nem o `validate()` (ambos O(N) baratos), é o `LevelSolver` com física em tempo real dentro do loop de geração. Em produção ele quase sempre estoura o orçamento e cai em `fallback/ultimate`.

### 1.3 Outros problemas encontrados (não bloquear a refatoração)

- `Game.tscn` sem script: impossível jogar a fase real hoje.
- `HUD` sem script e sem API: labels mortos.
- `LevelBuilder` não constrói chão: fase gerada flutua (Guide tem `Ground`, gerador não).
- Divergência `base_shot_speed` (`cannon.gd 1000` vs `LevelDefinition 2000` vs `CannonController.tscn 2000`) e `cannon_position` (`Guide 150,487` vs `LevelDefinition 173,523`).
- `play_bounds 1280×720` ignora que `WorldArea` em `Game.tscn` tem 200 px ocupados por controles.
- PRD/GDD pedem RN-04 com atenuações que o código não aplica (metal `1.0`, pedra `0.85`).

## 2. Arquitetura proposta

Manter o que está correto; tirar física do caminho crítico; dar ao `Game` o papel hoje acumulado pelo `Cannon Controller`.

- `FastLevelGenerator` (novo, `RefCounted`, puro): única porta de entrada da fase real. Recebe `(seed, level_number)` + `RandomNumberGenerator` próprio, retorna `LevelDefinition` com `solution` analítica anexada em milissegundos. Não instancia Nodes, não usa `await physics_frame`, não usa RNG global, não fala com UI. Determinístico: mesma `(seed, versão, fase)` → mesmo dicionário.
- `ProceduralLevelGenerator` + `LevelSolver` + `SimulationWorld` atuais: viram ferramenta offline/teste (validação, benchmark, calibragem). Não são mais chamados pelo `Game`. Não remover nesta refatoração — só desconectar do runtime.
- `LevelValidator` (atual, barato): continua como guarda geométrico dentro do `FastLevelGenerator` (pós-condição), sem física.
- `LevelBuilder` (atual + extensão mínima): continua transformando `LevelDefinition` em Nodes, mas passa a construir também o `Ground` (faixa base + `Target` + obstáculos). Sem escolha de posições, sem validação, sem RNG.
- `Game` (novo script em `screens/game.gd` anexado ao `Game.tscn`): orquestrador da fase real. Gera (chamada síncrona), manda construir, posiciona canhão, detém `ammo_total/ammo_left`, conecta `PowerSlider.power_changed → cannon.set_power`, `FireButton.pressed → shoot()`, `Target.hit → vitória`, esgotamento + ausência de balas → derrota, e publica `ammo_changed` para o HUD. Único dono do estado da fase.
- `HUD` (novo `hud.gd` mínimo, passivo): expõe `set_ammo(total, left)` (+ `set_level(n)` cosmético). Não conhece gerador, solver ou `LevelDefinition`. Não exibe fase/pontuação nesta etapa.
- `Cannon` (inalterado): atuador burro (`set_power`, `rotate_cannon`, `shoot(power)`, preview). Não controla munição nem regras.
- `Cannon Controller` (congelado): continua como está, apenas para testes rápidos. Não recebe features novas; não é usado pela fase real; divergências futuras com `Game` são aceitáveis.

Regra de acoplamento: gerador → dados; `Game` → coordena; `Builder` → instancia; `HUD` → exibe. Nenhuma seta volta (HUD nunca chama gerador; gerador nunca toca Node).

## 3. Novo fluxo de geração

1. Jogador entra em `Game.tscn`. `Game._ready()` mostra estado `"Gerando..."`, resolve `seed` (ex.: `randi()` ou passada pela `Home`) e `level_number` (v1: `1`).
2. `Game` chama `FastLevelGenerator.generate(seed, level_number)` de forma síncrona (sem `await` de física). Internamente:
   a. `cfg = DifficultyTable.get_config(level_number)` (reuso, sem mudança).
   b. `rng` com `seed = hash(seed:versão:level)`.
   c. Escolhe arquétipo permitido por `cfg` (mesma roleta de `pick_archetype`, com filtro `min_ammo <= cfg.ammo`).
   d. Calcula a **solução primeiro** (analítica, §5): alvo + ângulo/potência que acertam (tiro direto ou 1 espelho). Isso é o `SolutionRecord` (1 tiro na v1; `total_shots=1`).
   e. Posiciona obstáculos do arquétipo **preservando um corredor livre** ao redor da solução (raio `LANE_CLEARANCE=70` + meia-diagonal). O que precisa bloquear (muro `blocked_direct`, cerco `bunker`) é colocado por construção geométrica, não por sorteio cego.
   f. `LevelValidator.validate + validate_config`. Se reprovar, repete **só o passo e** com o mesmo `rng` (no máximo ~20 tentativas baratas, sem física). Não re-resolve a balística.
3. `Game` recebe `LevelDefinition` (+ `ms`, `score` para log) e chama `await builder.build($WorldArea/World, def)` (o único `await` é 1 `physics_frame` do `clear()`).
4. `Game` posiciona `Cannon` em `def.cannon_position`, define `ammo_total/ammo_left = def.ammo`, conecta `Target.hit`, chama `hud.set_ammo(ammo, ammo)` + `hud.set_level(n)`, libera mira/disparo.
5. `shoot()`: se `ammo_left>0`, `ammo_left-=1`, `cannon.shoot(power_slider.power)`, `hud.set_ammo(total, left)`. Vitória/derrota como hoje no controller (vitória imediata no `hit`; derrota quando `ammo_left==0` e sem `bullets` vivas ou timeout).
6. Troca de fase = `load_level(nova_seed, n+1)` repetindo 2–4. Mesma seed + mesma fase = mesma `LevelDefinition` (replay/debug grátis via `to_dict/from_dict`).

## 4. Regras derivadas do `Guide.tscn`

O `Guide.tscn` é o gabarito visual/jogável. Regras extraídas (medidas literais da cena):

- R1 — Canhão à esquerda: `x ≈ 38..173`, `y ≈ 487..523` (`Guide 150,487 scale 0.3`; `CannonController 38,697 scale 0.2`; `LevelDefinition 173,523`). Fixar `cannon_position` do `LevelDefinition` como fonte única (manter `173,523` na v1, documentar divergência do Guide).
- R2 — Chão contínuo na base: peças `floor.tscn 0.2` (≈100 px) em `y=670`, `x=50..1250`. Sem buracos sob alvo/canhão. Plataforma elevada opcional (`150,570 + 250,570`) como variação Fase 1–10.
- R3 — Alvo à direita, perto do chão ou parede: `x 950..1230`, `y 326..572` (`Guide 1230,572`; `ultimate 1000,326`; `spot_target 950..1200, 80..640`). Tamanho fixo 80x80. Zona de exclusão 100 px ao redor (só o chão pode invadir).
- R4 — Muro de bloqueio direto (fases 11+): 2–3 metais `0.2` (≈110 px) em coluna vertical `x≈1050`, espaçados 130 px (vão de 20 px entre bordas bloqueia a bala de 92 px sem violar `OVERLAP_MARGIN=8`). É o `blocked_direct` — manter geometria.
- R5 — Espelho de ricochete: 1 metal `0.2` deslocado `~220 px` da normal da rota (posição do `blocked_direct`), ou cerco `bunker` (3 metais a 210 px: cima/baixo/direita, boca aberta para o canhão).
- R6 — Calibres: vidro `0.1` (≈95 px, atravessável), pedra/metal `0.2` (≈100–110 px). Rotação só `0/90`. Escala `0.05..1.0`.
- R7 — Distâncias mínimas: canhão–alvo ≥ 500 px; nada a <150 px do canhão (exceto o próprio canhão); corredor do muzzle (`canhão → +280,-60`) sempre livre; alvo nunca cercado nos 4 eixos por metal (`TARGET_BOXED`).
- R8 — Dificuldade por fase (RN-06/PRD, já em `DifficultyTable`): 1–3 tiro aberto + 0–2 vidros fora da rota; 4–10 + pedra na rota; 11+ muro + ricochete mínimo 1–2, munição 4→3→2.
- R9 — Balística: ângulo `-20..83`, potência `0.3..1.0`, `base_shot_speed=2000`, gravidade do `ProjectSettings`. Preview mostra só início (`0.35 s / 400 px`).

## 5. Estratégia de performance

Por que sai de minutos para milissegundos:

- Elimina o termo dominante: `N_sims × 640 ms`. O novo caminho faz **zero simulações físicas** — `N_sims = 0`. Custo passa a ser `place (O(N)) + validate (O(N²) com N ≤ 12) + solução analítica (O(1))`, tudo em GDScript puro sem `await physics_frame`, sem instanciar `SimulationWorld`, sem tweens, sem `add_child`.
- Solução analítica em vez de BFS: para tiro direto, resolve-se a equação do projétil `p(t) = muzzle + v·t + ½·g·t²` para `p(t)=alvo` (escolhe arco baixo; se fora de `[-20,83]×[0.3,1.0]`, ajusta alvo dentro da faixa alcançável em vez de simular milhares de combinações). Para ricochete, usa **método do espelho**: reflete o alvo no plano do espelho (parede metal/chão) e resolve tiro direto ao alvo virtual — o ponto de interseção com o plano é o ponto de rebote; `bounce=1.0` do metal torna a reflexão exata sem simulação. Vidro/pedra na rota entram como atenuação conhecida (`×0.85` por atravessamento, tabela `MaterialRules`) — ajusta-se a potência para cima em vez de simular.
- Sem explosão combinatória: rejeição só geométrica (`fits()` + `LevelValidator`, microssegundos cada). Orçamento típico: 1 solução + ≤20 placements × ≤12 AABBs ≈ centenas de operações — folga de 3 ordens de magnitude abaixo dos 300 ms (RNF-004). Medição honesta: `Time.get_ticks_msec()` ao redor do `generate()` + log de `ms/candidates` como o gerador atual já faz.
- Estruturas: `RandomNumberGenerator` com seed (determinismo), AABB (`Rect2`) + grade espacial implícita (N pequeno dispensa quadtree), `Geometry2D.segment_intersects_segment` para corredor/oclusão, dicionários `to_dict/from_dict` já existentes para replay.
- O `LevelSolver` com física real continua existindo, mas fora do runtime: prova offline (testes headless) de que as fases do `FastLevelGenerator` são solucionáveis, sem custar tempo do jogador.

## 6. Integração Game + Cannon + HUD

- **Pertence ao `Game`** (`screens/game.gd`, novo): estado da fase (`current_def`, `ammo_total/left`, `level_number`, `game_over/won`), `load_level(seed, n)`, `shoot()`, detecção vitória/derrota (`_on_target_hit`, `_physics_process` com `END_DELAY`), mira por drag (`_unhandled_input` como no controller), fiação `power_slider.power_changed → cannon.set_power`, `fire_button.pressed → shoot()`, `hud.set_ammo/set_level`, instância própria de `Cannon` + `Level` dentro de `WorldArea/World`, `builder: LevelBuilder` filho. Também compensa o layout: `play_bounds` efetivo = viewport menos faixa 200 px de controles.
- **Pertence ao gerador** (`FastLevelGenerator` + `DifficultyTable/Config` + arquétipos + `LevelValidator` + `MaterialRules`): dados puros. Recebe `(seed, level)` e devolve `LevelDefinition` com `solution`. Nunca vê `Game`, `HUD`, `Cannon` ou `power_slider`.
- **Pertence ao HUD** (`hud.gd`, novo, ~20 linhas): `set_ammo(total, left)`, `set_level(n)` atualizando os 3 `Label`s existentes. Opcional: sinal interno se `FireButton/PowerSlider` precisarem de enable/disable por `ammo==0` — mas o disparo continua bloqueado no `Game`, não no HUD. Sem `set_score` nesta etapa (placar continua `"Pontos: 0"`).
- **Continua no `Cannon Controller`** (só testes): `load_level`, `shoot`, mira, `StatusLabel`, `Level` próprio, geração via `ProceduralLevelGenerator` lento. Não conectar ao `Game.tscn`, não exibir fase/score, não receber `hud.gd`. Serve para abrir `CannonController.tscn` e iterar física/mira rapidamente.

Contrato Game↔HUD (único acoplamento permitido): `Game` chama `hud.set_ammo(total, left)` após gerar e após cada disparo; HUD não retorna nada nem conhece `LevelDefinition`. `Game` lê `power_slider.power` no momento do disparo (não guarda cópia stale além de `cannon.set_power` para preview).

## 7. Estrutura de arquivos

Alterar (mínimo necessário):

- `screens/game.tscn` — adicionar `Cannon` (instância `cannon.tscn`), `Level: Node2D`, script `game.gd`; manter `World/Background/Controls/Hud` existentes.
- `components/level/level_builder.gd` — estender `build()` para instanciar o `Ground` (faixa base `y=670` + variações) a partir de constante (não de sorteio); marcar peças com `level_spawned`.
- `components/hud/hud.tscn` — só anexar `hud.gd` (sem redesenhar layout).

Criar:

- `screens/game.gd` — orquestrador (§6).
- `components/hud/hud.gd` — `set_ammo/set_level`.
- `components/level/fast_level_generator.gd` — geração analítica (§3/§5) + `FALLBACK` final = `ultimate` atual (alvo `1000,326`, sem obstáculos) se as 20 tentativas geométricas falharem (custo ainda em ms).

Preservar sem tocar (runtime não chama, testes usam):

- `procedural_level_generator.gd`, `level_solver.gd`, `simulation_world.gd/tscn`, `difficulty_scorer.gd`, `tests/*`, `guide/Guide.tscn`, `components/cannon-controller/*`, `material_rules.gd`, `level_definition.gd`, `obstacle_definition.gd`, `target_definition.gd`, `solution_record.gd`, `difficulty_table.gd`, `difficulty_config.gd`, `level_validator.gd`, arquétipos, `cannon.gd`, `power_slider.gd`, `target.gd`, `bullet.gd`, obstáculos.

Remover/refatorar: nada nesta etapa. Candidatos futuros (só observação): unificar `StatusLabel` do controller com `hud.tscn`; unificar `play_bounds` com área útil real; sincronizar PRD RN-04 com `material_rules.gd`.

## 8. Plano de implementação

1. `Game` mínimo carrega fase fixa — arquivos: `screens/game.gd` (novo), `screens/game.tscn`. Objetivo: `Game` instancia `Cannon` + `Level`, `builder.build` com `ultimate_fallback` atual, sem gerador. Alterações: criar `game.gd` com `load_level_fixa()`, adicionar nós `Cannon/Level` na cena. Dependências: nenhuma. Validar: abrir `Game.tscn`, ver canhão + alvo + chão, sem erros.
2. HUD exibe munição — arquivos: `components/hud/hud.gd` (novo), `hud.tscn` (anexar script), `game.gd`. Objetivo: `set_ammo/total/left` + `set_level`. Alterações: ~20 linhas, sem score. Dependências: etapa 1. Validar: label `Munição: X` muda após gerar e após disparar.
3. `Game` controla disparo — arquivos: `game.gd`, `game.tscn`. Objetivo: fiar `PowerSlider/FireButton/Cannon/ammo/estado` no `Game`, replicando a lógica do controller (vitória/derrota/mira). Alterações: `shoot()`, `_on_target_hit`, `_physics_process`, `_unhandled_input`, `power_changed`. Dependências: etapas 1–2. Validar: jogar fase fixa de ponta a ponta com slider + botão; `CannonController.tscn` intacto.
4. `Builder` constrói chão — arquivos: `level_builder.gd`. Objetivo: faixa base `y=670 x50..1250` (+ plataforma opcional) com `floor.tscn 0.2`, grupo `level_spawned`. Dependências: etapa 1. Validar: fase fixa com chão contínuo igual ao Guide; `clear()` remove tudo.
5. `FastLevelGenerator` tiro direto — arquivos: `fast_level_generator.gd` (novo). Objetivo: solução analítica + `open_shot/glass_barrier/stone_gate` preservando corredor, `validate` como guarda, determinístico, `ms` em log. Dependências: nenhuma (puro). Validar: teste headless gera fases 1–10, `validate ok`, `ms < 300`, mesma seed = mesmo dict.
6. Prova de solubilidade offline — arquivos: `tests/fast_generator_proof_test.gd` (novo, headless). Objetivo: rodar `LevelSolver` existente sobre amostra do `FastLevelGenerator` (fora do runtime). Dependências: etapa 5. Validar: taxa de solução ≈100% em amostra 1–10 sem travar o jogo.
7. Ricochete geométrico — arquivos: `fast_level_generator.gd` (+ `blocked_direct/bunker/combo_order`). Objetivo: espelho a 220 px / muro em coluna 130 px / cerco 210 px por construção + solução via alvo virtual. Dependências: etapas 5–6. Validar: fases 11+ com `required_ricochets_min` atendido na prova offline, ainda `ms < 300`.
8. Ligar `Game` no gerador rápido — arquivos: `game.gd`. Objetivo: trocar fase fixa por `FastLevelGenerator.generate(seed, n)` síncrono no `_ready`, `hud.set_ammo(def.ammo)`. Dependências: etapas 3, 5 (7 se 11+). Validar: entrar no `Game`, fase pronta em ms (log), jogar, trocar de fase, mesma seed = mesma fase; `ProceduralLevelGenerator` não é mais chamado pelo jogo.

## 9. Critérios de aceitação

- [ ] Fase gerada usa as regras do `Guide.tscn` (§4: canhão à esquerda, chão contínuo `y≈670`, alvo à direita, calibres `0.1/0.2`, distâncias/exclusões, muro/espelho 11+, balística `-20..83 / 0.3..1.0 / 2000`).
- [ ] Fase exibida corretamente em `Game.tscn` (canhão + alvo + obstáculos + chão, sem buracos, sem sobreposição canhão/muzzle/alvo).
- [ ] Geração concluída em milissegundos em condições normais (log `ms < 300`, RNF-004; sem `await physics_frame`, sem instanciar `SimulationWorld` no caminho do jogo).
- [ ] Quantidade de disparos definida pela fase (`def.ammo` via `DifficultyTable`, 1..4).
- [ ] HUD exibindo corretamente a quantidade de disparos (atualiza ao gerar e a cada tiro; sem fase/pontuação nesta etapa).
- [ ] `Game` controlando a integração canhão ↔ `PowerSlider` ↔ `FireButton` (força, botão, munição, estado da fase; vitória/derrota funcionam).
- [ ] `Cannon Controller` preservado apenas como ferramenta de teste (abre e joga sozinho, sem ser usado pela fase real).
- [ ] Fase jogável e coerente (prova offline via `LevelSolver` existente + playtest: existe tiro dentro de `[-20,83]×[0.3,1.0]` com `ammo` que atinge o alvo).
- [ ] Ausência de dependência de backend, internet ou IA (só `RandomNumberGenerator` com seed + matemática + geometria; jogo roda offline).

Observações fora do escopo obrigatório: unificar `StatusLabel`↔HUD; corrigir `play_bounds` útil (descontar 200 px de controles); alinhar `cannon_position/base_shot_speed` entre Guide/Definition/Cannon; sincronizar PRD RN-04 com `material_rules.gd`; física acelerada (step manual) se um dia quiserem o solver em runtime.
