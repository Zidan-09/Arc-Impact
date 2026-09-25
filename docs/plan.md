# Plano Técnico — Geração Procedural de Fases (Arc-Impact)

> **Status:** planejamento apenas. Nenhum sistema descrito aqui está implementado.
> **Escopo:** apenas `docs/plan.md` foi criado nesta etapa.

---

## 1. Objetivo

Construir um sistema offline, determinístico por seed e extensível que:

1. Gere fases jogáveis infinitas sem conteúdo pré-autorado.
2. Posicione canhão (fixo), alvo, obstáculos (vidro/metal/pedra + futuros) e defina munição (1–4 tiros, conforme RN-03 do PRD).
3. Garanta por construção + verificação que **existe pelo menos uma solução** com a munição dada.
4. Rejeite fases inválidas/impossíveis e gere outra (com limite de tentativas + fallback).
5. Meça e controle dificuldade de forma objetiva (não só "mais obstáculos").
6. Separe **dados da fase** (`LevelDefinition`) de **instanciação de Nodes** (`LevelBuilder`), para testabilidade e para futura evolução (novos materiais, mecânicas).
7. Rode bem em dispositivo modesto e respeite o orçamento do PRD (RNF-004: geração+validação ≤ 300 ms).

Fluxo canônico:

```text
seed + difficulty + generatorVersion
  ↓
ProceduralLevelGenerator (candidatos via arquétipos + RNG com seed)
  ↓
LevelDefinition (dados puros, serializáveis)
  ↓
LevelValidator (regras baratas: limites, sobreposição, munição, sanidade)
  ↓ (se passar)
LevelSolver (simulação física headless, busca limitada)
  ↓ (se solução encontrada)
LevelBuilder / LevelLoader (LevelDefinition → Nodes reais)
  ↓
fase jogável + SolutionRecord (usado para calibrar dificuldade)
```

Fora de escopo desta etapa: backend, internet, IA em runtime, multiplayer, level editor, loja/cosméticos, persistência com checksum (apenas prever o campo de save).

---

## 2. Análise do projeto atual

### 2.1 Arquivos e classes relevantes

| Arquivo | Papel hoje | Relevância para o gerador |
|---|---|---|
| `project.godot` | Viewport `1280x720`, `stretch=canvas_items/expand`; física 2D padrão (gravidade default ~980, sem override); `main_scene=uid://c5seybfpkbukl` (`screens/game.tscn`) | Define o **playfield de referência**. O solver e o validador precisam de limites explícitos derivados daqui. Nenhum `physics/common/physics_ticks_per_second` customizado — fixar em 60 na implementação para determinismo. |
| `screens/game.tscn` | `Control` raiz + `Background` + `World: Node2D` (vazio) + `Hud` | `World` é o ponto natural de montagem da fase gerada. Hoje nada instancia fase aqui. |
| `components/cannon-controller/CannonController.tscn` | **Fase de teste manual**: `Cannon` em `(173, 523)` + `PowerSlider` + ~5 vidros + ~7 metais + 4 pedras posicionados à mão + `FireButton` | Prova de que **não existe loader**: fase = cena editada à mão. Será refatorada para cena mínima (canhão + slots) + `LevelLoader` que limpa/instancia `LevelDefinition`. Posições atuais servem como referência de escala, não como formato final. |
| `components/cannon-controller/cannon_controller.gd` | `shoot() -> cannon.shoot(power_slider.power)`; arrasto de ângulo via `_unhandled_input`; `FireButton.pressed -> shoot()` | Ponto de integração: o loader precisará setar `cannon.current_angle`, `power_slider.power` inicial e contador de munição (hoje inexistente). |
| `components/cannon/cannon.tscn` + `cannon.gd` | `BarrelPivot` + `Muzzle: Marker2D` em `(267,-48)` local; paredes `SegmentShape2D` (guia do cano); `BulletReturnDetector: Area2D` que deleta o bullet; `shoot(power)`: instancia `bullet_scene`, `add_child` em `current_scene`, `linear_velocity = dir * 2000 * power`; ângulo `min=-20 / max=83`, `current=45`, `base_shot_speed=2000` | **Fonte da verdade do disparo.** O solver deve replicar exatamente: origem = `muzzle.global_position`, direção = `Vector2.RIGHT.rotated(muzzle.global_rotation)`, velocidade = `2000 * power`, `power ∈ [0.3, 1.0]` (faixa do slider). Atenção: `shoot()` adiciona o bullet em `current_scene`, não no `World` — o builder/solver precisam decidir o parent canônico (recomendação: `World`). |
| `components/bullet/bullet.tscn` + `bullet.gd` | `RigidBody2D` + `CircleShape2D r=46.17` + `HitDetector: Area2D r=56` que chama `body.hit(self, global_position)`; `del_bullet() -> queue_free()` | **Duplo sistema de colisão**: (a) física rígida real (rebote) + (b) detecção lógica via `Area2D`. O solver **não pode** usar só geometria/raycast: precisa simular o `RigidBody2D` real, senão o rebote diverge do jogo. `mass/damping/gravity_scale` estão no default — registrar como parâmetros congelados do solver. |
| `components/cannon/bullet_return_detector.gd` | `Area2D` com `RectangleShape2D (36x136)` que chama `del_bullet()` | Define condição de **fim de voo** além de "parou" ou "saiu da tela". O solver precisa do mesmo predicado de término. |
| `components/obstacles/obstacle.gd` (`class_name Obstacle`) | `StaticBody2D` base; `hit()` com `await play_hit_animation()` (~0.30 s) + revalidação de bullet liberado (fix anterior); `hit_scale=1.08`, `hit_duration=0.15` | O `await` + tween torna o estado do obstáculo **temporal**. Para o solver, a animação é irrelevante (só visual) — modelar como transição instantânea de HP/visibilidade. Não simular tweens no solver. |
| `components/obstacles/metal/metal_obstacle.gd` + `metalObstacle.tscn` | `StaticBody2D` + `RectangleShape2D (548x548)`; `PhysicsMaterial friction=0, bounce=1.0`; `on_hit_completed = pass` (indestrutível) | Ricochete "real" via motor de física (`bounce=1.0`), não via código. É o motivo central pelo qual **solver analítico puro falha**: o ângulo de saída depende do integrador + material + forma. |
| `components/obstacles/stone/stone_obstacle.gd` + `stoneObstacle.tscn` | `StaticBody2D` + `RectangleShape2D (500x500)`; `bounce=1.0`; `stoneLife=2`; 1º hit racha (via base), 2º hit destrói: `bullet.linear_velocity *= 0.85`, spawna shards, `queue_free` após 2 `physics_frame` | Estado **multi-hit com ordem**: o mesmo bloco muda o resultado do 2º tiro. O solver precisa de **estado por obstáculo entre tiros** (intacto → rachado → destruído) e da regra `velocity_retain=0.85`. |
| `components/obstacles/glass/glass_obstacle.gd` + `glassObstacle.tscn` | `StaticBody2D` + filho `HitBox: Area2D (952x934)`; `hit()` destrói no 1º impacto: `bullet.linear_velocity *= 0.85`, spawna shards, `queue_free` imediato | Ponto sutil: o corpo é `StaticBody2D` mas a detecção é via `Area2D` filho — **o projétil atravessa** (não há `CollisionShape2D` sólido no corpo). O solver deve modelar vidro como "atravessável com atenuação 0.85 + remoção", não como rebote. |
| `components/obstacles/shard.gd`, `stone_shard.gd`, `glass_shard.gd`, `stone_shard.tscn`, `glass_shard.tscn` | `RigidBody2D (60x60, mass=0.2, bounce=0.3)` com `lifetime=3.0`; `_spawn_shards()` usa `randf_range`/`randf` **global** | **Bloqueador de determinismo atual**: shards usam RNG global. Não afetam vitória diretamente (`if bullet is Shard: return`), mas poluem a simulação e quebram reprodutibilidade se o solver instanciar shards. Decisão registrada: solver **não instancia shards** (são cosméticos); e na implementação, trocar `randf_range` por RNG com seed ou marcar shards como `collision_layer/mask` que não interage com o validador. |
| `components/power-slider/power_slider.gd` + `powerSlider.tscn` | `power ∈ [0.3, 1.0]`, `sensitivity=0.0012`; drag via `gui_input` | Define a **discretização real do input**: o solver deve amostrar dentro de `[0.3, 1.0]`, não `[0, 1]`. |
| `components/hud/hud.tscn`, `components/fire-button/fireButton.tscn` | HUD com `Phase/Points/Shoots` (estáticos) + `FireButton: TextureButton` | Contador de tiros e condição de vitória/derrota **não existem como lógica**. O gerador precisa introduzir `ammo` e `Target` como dados; a UI só reflete. |
| `docs/PRD.md`, `docs/GDD.md` | RN-01 (ângulo 0–90, força 10–100%), RN-03 (munição 1–4), RN-04 (frágil 1HP −15%, equilibrado 2HP, resistente ∞ ricochete −5%), RN-06 (D baixa ≤10 sem ricochete, D alta 11+ com 1–3 ricochetes), RNF-004 (≤300 ms) | Referência de regras. **Divergências reais encontradas** (registrar, não corrigir agora): (a) código usa `velocity_retain=0.85` para vidro/pedra, não 15%/30% exatos do PRD; (b) metal usa `bounce=1.0` do motor, sem atenuação explícita de 5%; (c) ângulo real do `cannon.gd` é `[-20, 83]`, não `[0, 90]`; (d) força real é `[0.3, 1.0]`, não `[0.1, 1.0]`. O plano usa os **valores do código** como verdade e propõe sincronizar os docs na implementação. |

### 2.2 Como a física realmente funciona (resumo para o solver)

- Disparo: posição do `Muzzle`, velocidade inicial `2000 * power` na direção do cano. Sem gravidade customizada → usará a default do Godot. Projétil é dinâmico e interage com `StaticBody2D` (metal/pedra) via contato rígido + com `Area2D` (vidro `HitBox`, `HitDetector` do bullet, `BulletReturnDetector`) via sinais.
- Metal/pedra: rebote emergente do motor (`bounce=1.0`, `friction=0`). Não há `CALCULAR_REFLEXAO` manual no código atual (o pseudocódigo do PRD §6.4 **não corresponde** ao código real). Conclusão: **qualquer solver baseado em reflexão analítica vai divergir**; é preciso simulação passo a passo do `RigidBody2D`.
- Vidro: sem colisor sólido → não desvia, só atenua (`*= 0.85`) e some. Pedra no 2º hit: atenua (`*= 0.85`) e some após 2 physics frames (reaplica velocidade para atravessar o corpo que está sendo liberado).
- Shards: `RigidBody2D` independentes, ignorados por obstáculos (`is Shard -> return`), deletados pelo `BulletReturnDetector` se encostarem. São ruído para o solver.
- Fim de um tiro: bullet liberado (`del_bullet`), ou parado, ou timeout, ou fora dos limites. Hoje não há timeout global nem kill-plane — o plano precisa criar.

### 2.3 O que não existe e o gerador vai precisar criar

- **Alvo (`Target`)**: nenhuma cena/script. Será `Area2D` nova (`components/target/`).
- **Sistema de fase**: sem `LevelDefinition`, sem loader, sem canditados, sem validação, sem solver, sem contador de munição, sem vitória/derrota.
- **Limites do cenário**: sem paredes/kill-plane configurados; fase de teste é aberta. O validador precisa de um `PlayBounds` explícito.
- **Randomização com seed**: só existe RNG global nos shards. Nada usa `RandomNumberGenerator` com seed.
- **Testes**: nenhum framework (`GUT`/`GdUnit`) nem teste headless.

---

## 3. Arquitetura proposta

### 3.1 Componentes e responsabilidades

Seguir o padrão existente `components/<nome>/` (um `.gd` + cenas), sem framework genérico.

| Componente | Arquivo(s) proposto(s) | Responsabilidade | Não faz |
|---|---|---|---|
| `LevelDefinition` | `components/level/level_definition.gd` (extends `Resource`) | Dado puro e serializável da fase: seed, versão do gerador, dificuldade, canhão, alvo, lista de obstáculos, munição, `PlayBounds`, `SolutionRecord`. Capaz de `to_dict()/from_dict()` para save/debug. | Não instancia Nodes, não roda física, não usa RNG. |
| `ProceduralLevelGenerator` | `components/level/procedural_level_generator.gd` (extends `RefCounted`) | Gera `LevelDefinition` candidatos a partir de `seed + DifficultyConfig + arquétipo`. Único dono de um `RandomNumberGenerator` com seed explícita. Orquestra `Validator → Solver → aceita/rejeita`. | Não cria Nodes, não usa `randf_global`, não simula física diretamente (delega ao solver). |
| `LevelValidator` | `components/level/level_validator.gd` (`RefCounted`) | Checagens **baratas e sem física**: limites, sobreposição, distância mínima, munição válida, sanidade do arquétipo, integridade (ex.: alvo alcançável por bounding box). Retorna `ValidationResult { ok, erros[], warnings[] }`. | Não decide solucionabilidade final (isso é do solver). |
| `LevelSolver` | `components/level/level_solver.gd` (`RefCounted`) + `simulation/` auxiliar | Responde: "existe sequência de ≤ N tiros que atinge o alvo?" via **amostragem discretizada + simulação física headless determinística**. Retorna `SolutionRecord` (tiros usados, ângulo/força por tiro, nº de ricochetes, nº de soluções encontradas, precisão exigida). | Não gera fases, não toca na cena visível (roda em cena separada/oculta), não roda durante o gameplay. |
| `LevelBuilder` / `LevelLoader` | `components/level/level_builder.gd` (`Node`) + ajuste em `CannonController.tscn` | Transforma `LevelDefinition` em Nodes: limpa `World`, instancia alvo + obstáculos nas transforms, configura munição/HUD, posiciona canhão. | Não escolhe posições, não valida, não resolve. |
| `Target` (novo) | `components/target/target.tscn` + `target.gd` (`Area2D`, `signal hit`) | Área de vitória. Tamanho fixo documentado (ex.: `80x80`, a calibrar). | Não participa da geração. |
| `DifficultyConfig` | `components/level/difficulty_config.gd` (`Resource`) | Tabela por nível: nº de obstáculos por tipo, munição, arquétipos permitidos, ricochetes exigidos, tolerância de precisão. | Não contém lógica de busca. |
| `LevelArchetypes` | `components/level/archetypes/*.gd` (um script por arquétipo, mesma interface) | Estratégias de posicionamento (ver §9). Registro extensível sem tocar o núcleo. | Não validam nem resolvem. |

### 3.2 Diagrama textual

```text
                    +-------------------+
                    |  Game / LevelLoader|
                    | (CannonController) |
                    +---------+---------+
                              | request(seed, level_number)
                              v
                    +-------------------+      +------------------+
                    | ProceduralLevel   |----->| DifficultyConfig |
                    | Generator (RNG)   |      | (tabela por fase)|
                    +---------+---------+      +------------------+
                              | gera LevelDefinition candidato
                              v
                    +-------------------+      +------------------+
                    | LevelValidator    |----->| PlayBounds, regras|
                    | (barato, sem física)|    | de sobreposição   |
                    +---------+---------+      +------------------+
                              | ok? ---------- não --> descarta, próximo candidato
                              v sim
                    +-------------------+
                    | LevelSolver       |
                    | (amostragem +     |
                    |  física headless) |
                    +---------+---------+
                              | solução? ----- não --> descarta, próximo candidato
                              v sim (+ SolutionRecord)
                    +-------------------+
                    | LevelBuilder      |--> instancia em World
                    +-------------------+
```

Decisão arquitetural D1: **dados primeiro, Nodes depois**. `LevelDefinition` é `Resource` puro para permitir testes headless sem abrir cena, serialização para debug (`seed -> mesma fase`) e futura persistência de save.
Decisão D2: **solver fora do gameplay**. Ele só roda na geração (com orçamento de tempo). Durante o jogo, a física real assume.
Decisão D3: **não simular tweens/shards/HUD** no solver. Só `RigidBody2D` do bullet + colisores estáticos + `Area2D` do alvo + regras de HP/atenuação.

---

## 4. Modelo de dados

### 4.1 `LevelDefinition` (Resource)

```gdscript
# components/level/level_definition.gd
class_name LevelDefinition extends Resource
@export var seed: int
@export var generator_version: int   # ex.: 1; bump quando o algoritmo mudar
@export var level_number: int
@export var ammo: int                # 1..4 (RN-03)
@export var cannon_position: Vector2 # fixo na v1 (ex.: 173,523), mas modelado
@export var cannon_angle_min: float  # espelha cannon.gd (-20)
@export var cannon_angle_max: float  # espelha cannon.gd (83)
@export var power_min: float         # 0.3
@export var power_max: float         # 1.0
@export var base_shot_speed: float   # 2000.0
@export var play_bounds: Rect2       # ex.: (0,0,1280,720) + margens
@export var target: TargetDefinition
@export var obstacles: Array[ObstacleDefinition]
@export var solution: SolutionRecord # preenchido pelo solver (opcional p/ debug)
```

### 4.2 `ObstacleDefinition`

```gdscript
class_name ObstacleDefinition extends Resource
@export var id: String               # "obs_01" (determinístico: índice)
@export var kind: StringName         # &"glass" | &"metal" | &"stone" (extensível)
@export var position: Vector2
@export var rotation_degrees: float  # v1: 0 ou 90 (simplifica validação); liberar depois
@export var scale: Vector2           # v1: fixo por tipo (ex.: metal 0.2); liberar depois
# HP e física vêm do tipo (vidro 1, pedra 2, metal INF), não duplicar aqui.
```

Tamanhos de referência (do `.tscn` atual, escala 1.0): metal `548x548`, pedra `500x500`, vidro `952x934` (hitbox). Com `scale=0.2` (padrão da cena de teste), metal ≈ `110x110`. O validador usa `tamanho_base * scale` rotacionado como AABB aproximado.

### 4.3 `TargetDefinition`

```gdscript
class_name TargetDefinition extends Resource
@export var position: Vector2        # faixa direita: x ∈ [950, 1200], y ∈ [80, 640]
@export var size: Vector2            # ex.: (80, 80) — FIXO na v1
```

### 4.4 `DifficultyConfig` (Resource + tabela)

```gdscript
class_name DifficultyConfig extends Resource
@export var level_number: int
@export var ammo: int
@export var max_obstacles: int
@export var glass_count: Vector2i    # (min, max)
@export var stone_count: Vector2i
@export var metal_count: Vector2i
@export var required_ricochets_min: int  # 0 (fase ≤10) ou 1..3 (fase 11+)
@export var allowed_archetypes: Array[StringName]
@export var solver_angle_step: float     # ex.: 2.0° (grosso) — pode apertar por dificuldade
@export var solver_power_step: float     # ex.: 0.1
```

Curva inicial (traduz RN-06): fases 1–3 só vidro, tiro direto; 4–10 vidro+pedra; 11+ introduz metal bloqueando a reta + exige ricochete; munição `1–4` decrescente com dificuldade (mais difícil = menos sobra).

### 4.5 `SolutionRecord`

```gdscript
class_name SolutionRecord extends RefCounted
var shots: Array[Dictionary]  # [{angle, power, ricochets, destroyed:[ids]}]
var total_shots: int
var total_ricochets: int
var solutions_found: int      # quantas combinações passaram (p/ medir dificuldade)
var min_angle_margin: float   # menor perturbação que ainda passa (precisão exigida)
```

### 4.6 Persistência

`LevelDefinition.to_dict()` → JSON para log de fase ruim (`seed`, `generator_version`, erros do validador/solver). Save do jogador guarda `highestLevelReached + seed_por_fase` (não o layout inteiro — regenera deterministicamente).

---

## 5. Algoritmo de geração (passo a passo)

Entrada: `(seed, level_number)`. Saída: `LevelDefinition` validada + resolvida, ou falha controlada.

1. `rng = RandomNumberGenerator.new(); rng.seed = hash(seed, generator_version, level_number)`.
2. Carrega `DifficultyConfig` da fase (tabela, sem RNG).
3. Sorteia `ammo` dentro da faixa da dificuldade.
4. Escolhe arquétipo em `allowed_archetypes` via `rng` (ver §9). Ex.: fase 1–3 → `open_shot`; 11+ → `blocked_direct`.
5. Posiciona o **alvo**: `x = rng.randf_range(950, 1200)`, `y = rng.randf_range(80, 640)`, respeitando margem do `PlayBounds` e distância mínima do canhão (ex.: `> 500 px`).
6. O arquétipo posiciona obstáculos **evitando a solução por construção** (não aleatório puro):
   - Primeiro define uma "faixa solução" (tiro direto canhão→alvo, ou via 1 ponto de rebote em parede/metal).
   - Depois coloca bloqueios/decorativos **fora** dessa faixa (com margem de segurança = raio do bullet `~46 px * escala` + folga).
7. Validação barata (`LevelValidator`). Se falhar → volta ao passo 4/5 (novo candidato com o mesmo `rng` avançando — **não** recriar o RNG, para manter determinismo da sequência).
8. Solver (ver §7). Se achar solução → anexa `SolutionRecord`, mede dificuldade real, aceita se dentro da banda desejada; senão descarta e tenta de novo.
9. Se esgotar `MAX_CANDIDATES` (ex.: 40), usa fallback: seed fixa pré-testada da mesma dificuldade (lista `FALLBACK_SEEDS`).

Por que não "aleatório puro + solver filtra": com física de rebote, a taxa de acerto aleatória é baixíssima e estouraria os 300 ms. Arquétipo + faixa solução inverte a probabilidade (maioria nasce válida).

---

## 6. Algoritmo de validação (`LevelValidator`)

Ordem crescente de custo, com early-exit. Cada regra retorna código de erro para log.

1. **Limites**: tudo dentro de `play_bounds` (com margem de meio-tamanho). Canhão fixo dentro. Alvo dentro da faixa direita.
2. **Sobreposição inválida**: AABB (posição + tamanho*scale + rotação 0/90) de cada obstáculo vs. canhão (ponto + raio de exclusão `~150 px`), vs. alvo (exclusão `~100 px`), vs. outro obstáculo (exclusão = soma dos meios-tamanhos + `folga 8 px`). O(n²) com n ≤ ~12, trivial.
3. **Posições impossíveis**: alvo a menos de `X px` do canhão; obstáculo cobrindo 100% do `Muzzle` (raycast curto canhão→frente); metal formando caixa fechada ao redor do alvo (checar se os 4 lados estão bloqueados por AABB — aproximação conservadora).
4. **Munição**: `1 <= ammo <= 4`; se arquétipo exige destruir k pedras (2 hits cada), exige `ammo >= ceil(hits_necessários)` estimado.
5. **Integridade**: `kind` conhecido, `scale` dentro da faixa, `rotation` em `{0, 90}` na v1, `generator_version` suportada.
6. **Sanidade de dificuldade**: contagem por tipo dentro da `DifficultyConfig`.

O validador **não** simula física e **não** aprova sozinho — só reprova rápido o que é estruturalmente errado.

---

## 7. Solver (`LevelSolver`) — o ponto mais importante

### 7.1 Por que geometria/raycast simples não basta (evidência do código)

- O rebote de metal/pedra é **emergente do integrador `RigidBody2D` + `PhysicsMaterial(bounce=1.0)`**, não uma reflexão geométrica perfeita. Velocidade angular, `friction`, ordem de contato e `physics_frame` alteram a saída.
- Vidro **não rebate** (atravessa com `*= 0.85`); pedra no 2º hit **atravessa** após 2 frames (reaplica velocidade). Um `intersect_ray` diria "bloqueado" onde o jogo diz "atravessa".
- `StoneLife=2` cria **dependência de ordem entre tiros**: o estado do tiro 2 depende do que o tiro 1 destruiu. Solução = sequência, não um único vetor.
- Conclusão: o solver precisa **executar a mesma integração física do jogo**, com as mesmas constantes, e observar o resultado.

### 7.2 Alternativas consideradas

| Alternativa | Ideia | Veredito |
|---|---|---|
| A. Balística analítica + reflexão especular | Equações de projétil + `θi=θr` em retângulos | **Rejeitada.** Ignora integrador, `bounce`, atenuações por código (`0.85`), atravessamento de vidro/pedra eмульти-hit. Divergiria do jogo real. |
| B. `PhysicsRayQueryParameters2D` amostrado | Raios canhão→cenário, recursão em rebotes | **Rejeitada como decisor.** Serve como heurística/poda (tiro direto livre?), mas não modela perda de velocidade, destruição nem sequência multi-tiro. |
| C. Busca exata (A*/BFS contínuo) sobre espaço (ângulo, força) | Grafo com heurística de distância ao alvo | **Rejeitada como núcleo.** Espaço de ação é contínuo e a transição é cara (simulação). Não há heurística admissível confiável com rebotes/destruição. A* degeneraria para amostragem. |
| D. **Amostragem discretizada + simulação headless + BFS limitada por tiros (escolhida)** | Grade (ângulo × força) → simula cada tiro no motor real → BFS até `ammo` de profundidade, com estado de HP entre tiros | **Escolhida.** É a única que responde "existe sequência de ≤ N tiros no jogo real?". Custo controlado por discretização + early-exit + cache. |
| E. Reverse-solving puro (gerar trajetória e colocar obstáculos em cima) | PRD §5.4 | **Adiada para v2.** Exige inverter o integrador (difícil). A v1 usa "arquétipo com faixa solução" (§5), que é um reverse-solving aproximado e honesto, sem alegar inversão exata. |

### 7.3 Algoritmo escolhido (D) — detalhe

```text
solve(def) -> SolutionRecord ou null:
  state0 = { stone_hp: {id:2}, glass_alive: {id:bool}, metal: sempre vivo }
  fronteira = [(state0, [])]   # BFS por nº de tiros
  para depth em 1..def.ammo:
    para cada (state, seq) na fronteira:
      para (angle, power) na GRADE (ex.: angle passo 2°, power passo 0.1):
        resultado = simulate_shot(def, state, angle, power)
        # resultado: { hit_target, ricochets, destroyed:[ids], end_state }
        se resultado.hit_target: registra solução; incrementa solutions_found
          se solutions_found >= EARLY_EXIT_COUNT (ex.: 3): retorna melhor solução
        senão: enfileira (resultado.end_state, seq+[tiro]) p/ próxima profundidade
          (com poda: descarta estados já visitados — hash de HPs + limite de ramificação)
  retorna melhor solução ou null
```

`simulate_shot`: instancia **cópia invisível** da fase em uma cena de simulação dedicada (`SimulationWorld: Node2D` fora da árvore visível, com mesmo `gravity`, `physics_material`s e scripts reais de `Metal/Stone/Glass/Target`), dispara um bullet real com os mesmos parâmetros do `cannon.gd`, avança com `await physics_frame` até condição de término (alvo atingido | bullet liberado | velocidade `< 30 px/s` por `0.5 s` | timeout `6 s` | saiu de `play_bounds` expandido). Registra ricochetes (contador de contatos com metal/pedra via sinal ou monitoramento de `linear_velocity`), IDs destruídos e estado final de HPs. Depois libera a cópia.

Estado entre tiros: clona `stone_hp`/`glass_alive`; metal nunca muda; pedra rachada (`hp=1`) persiste para o próximo tiro da mesma sequência — modela ordem e multi-hit.

Grade inicial (calibrar): ângulo `[-20, 83]` passo `2.0°` (~52 valores) × força `[0.3, 1.0]` passo `0.1` (8 valores) = ~416 simulações por profundidade no pior caso. Com poda + early-exit + timeout curto, cabe no orçamento (ver §11). Refinamento adaptativo: se achar "quase" (passou a `< 60 px` do alvo), reamostra vizinhança com passo fino (`0.5° / 0.05`) para medir precisão exigida (dificuldade).

Critério de acerto: colisão real com o `Area2D` do alvo na simulação (não distância). Tolerância de precisão = menor perturbação (Δângulo/Δforça) que mantém acerto — alimenta §8.

### 7.4 O que o solver considera (checklist do enunciado)

- Ângulos: sim (grade + refinamento). Forças: sim (`power` discretizada). Trajetórias: sim (integração real, não curva ideal). Colisões/ricochetes: sim (motor + contagem). Destruição: sim (vidro some, pedra 2 hits, atenuação `0.85`). Munição: sim (profundidade BFS ≤ `ammo`). Ordem: sim (estado entre tiros + BFS). Estados pós-tiro: sim (HPs clonados). Multi-solução: conta até `EARLY_EXIT_COUNT` para medir dificuldade.

---

## 8. Sistema de dificuldade

Princípio: dificuldade = **medida na solução encontrada**, não só contagem de blocos.

Métrica objetiva (v1, simples e extensível):

```text
difficulty_score =
    w1 * shots_usados
  + w2 * total_ricochetes
  + w3 * pedras_destruídas
  + w4 * (1 / max(0.01, min_angle_margin_deg))   # precisão exigida
  + w5 * (1 / max(1, solutions_found))           # raridade de soluções
  + w6 * (distância_canhão_alvo / diagonal_tela)
```

Pesos iniciais (a calibrar com playtest): `w1=3, w2=2, w3=1.5, w4=1, w5=2, w6=1`. Cada `DifficultyConfig` define banda aceitável `[score_min, score_max]` por faixa de fase. O gerador rejeita candidato cujo `score` saia da banda (além de rejeitar sem solução).

Controles por fase (alavancas, sem complicar): `ammo` (menos sobra = mais difícil), `metal_count` (mais rebotes forçados), `required_ricochets_min`, `allowed_archetypes`, `solver_angle_step` (grade mais grossa nas fases fáceis = soluções "largas"; refinamento mostra se a solução é estreita).

Exemplo: fase resolvida em 1 tiro direto com 12 soluções na grade → score baixo → aceita para fase 1–3, rejeita para 15+ (pede mais ricochetes/precisão).

---

## 9. Arquétipos

Sim, usar arquétipos — aleatório puro reprova demais no solver e gera fases sem leitura tática.

Interface única ( Strategy, sem tocar o núcleo):

```gdscript
class_name LevelArchetype extends RefCounted
func id() -> StringName: return &"base"
func place(def: LevelDefinition, rng: RandomNumberGenerator, cfg: DifficultyConfig) -> void: pass
```

Catálogo v1 (6, suficiente para infinito por combinação + seed):

1. `open_shot` — alvo à vista, 0–2 vidros fora da reta. (Fases 1–3.)
2. `glass_barrier` — 1–3 vidros **na** reta (atravessáveis, ensinam atenuação).
3. `stone_gate` — 1–2 pedras exigindo 2 hits ou contorno; testa munição >1.
4. `blocked_direct` — parede metal bloqueando a reta + 1 metal lateral como "espelho" (ricochete obrigatório). (Fases 11+.)
5. `bunker` — alvo semi-cercado (3 lados), entrada por cima/rebote.
6. `combo_order` — vidro na frente de pedra: ordem importa (gastar tiro no vidro antes).

Seleção: `allowed_archetypes` da dificuldade + `rng`. Novos tipos (botão/portão/levitação do PRD) entram como novos arquétipos + `ObstacleDefinition.kind` novo, sem alterar gerador/validador/solver (solver ganha regra de transição por tipo em tabela, não `if` espalhado — ver §15 etapa 2).

Cada arquétipo declara `min_ammo` e `required_ricochets` esperados; o validador confere coerência com a `DifficultyConfig`.

---

## 10. Determinismo (seed)

- `RandomNumberGenerator` **local** ao gerador: `rng.seed = hash(seed, generator_version, level_number)`. Nunca `randomize()`, nunca `randf_range` global no caminho de geração. Auditar: `glass/stone_obstacle.gd::_spawn_shards` usam RNG global — **fora** do caminho de geração/solver na v1 (solver não instancia shards; builder instancia visual depois, sem influenciar solução). Na implementação, migrar shards para RNG próprio ou `collision_mask` neutra.
- Mesma `(seed, generator_version, level_number, DifficultyConfig)` → mesmo `LevelDefinition` byte a byte (posições com `snappedf(..., 0.01)` para evitar ruído float).
- `generator_version: int` no `LevelDefinition` e no save. Se o algoritmo mudar, bump de versão; fases antigas regeneram com a versão gravada ou caem em fallback (nunca "mesma seed, fase diferente silenciosamente").
- Física determinística: fixar `physics/common/physics_ticks_per_second=60`, `base_shot_speed`, massas, materiais e `PlayBounds` como constantes versionadas. Documentar que determinismo Godot é "mesma plataforma/versão" — o contrato é regeneração local, não replay cross-engine.
- `SolutionRecord` opcionalmente persistida para debug, mas a verdade é re-simular: `seed -> solve -> mesma solução`.

---

## 11. Performance

Orçamento (RNF-004): geração + validação + solver ≤ 300 ms por fase em mobile intermediário. Estratégia:

- **Validador antes do solver**: reprova 80%+ dos ruins em microssegundos (AABB), sem física.
- **Discretização controlada**: grade grossa primeiro (`2.0° × 0.1`), refinamento fino só em "quase". `MAX_CANDIDATES=40`, `EARLY_EXIT_COUNT=3` soluções, profundidade BFS ≤ `ammo` (≤4), ramificação podada por estados visitados (hash de HPs) e por "tiro inútil" (sem contato e sem alvo → não expande).
- **Simulação enxuta**: cena de simulação mínima (só colisores + alvo + 1 bullet; sem shards, sem tweens, sem HUD, sem `Background`); `timeout 6 s` simulados com aceleração (`Engine.time_scale` local ou step manual — a definir na implementação, com fallback a timeout de wall-clock `~8 ms` por shot); `queue_free` imediato entre shots (evita acúmulo).
- **Cache**: AABBs por tipo/escala pré-computados; `DifficultyConfig` carregada uma vez; cena de simulação reutilizada (reset em vez de reinstanciar tudo).
- **Assíncrono**: geração roda fora do frame crítico (`await` por lote de candidatos ou `Thread` para a parte sem Nodes + volta à main para instanciar). Nunca durante o gameplay — só na transição de fase, com tela de "gerando" se exceder 1 frame. Se exceder `TIME_BUDGET_MS`, aborta e usa `FALLBACK_SEEDS`.
- **Medição**: `Time.get_ticks_msec()` ao redor de cada estágio; loga `seed, candidatos, simulações, ms` para calibrar a grade.

Estimativa honesta: 416 simulações × ~1–2 ms (mínimas) ≈ 400–800 ms no pior caso sem poda — por isso early-exit + validador + arquétipos são obrigatórios, não opcionais. A calibragem da grade é critério de aceite (ver §14).

---

## 12. Integração com as cenas atuais

Arquivos a alterar (quando a implementação for autorizada — **não agora**):

1. **Novo** `components/target/target.tscn` + `target.gd` (`Area2D`, `signal hit`, colisor `80x80`, grupo `"target"`).
2. **Novo** `components/level/*`: `level_definition.gd`, `difficulty_config.gd`, `procedural_level_generator.gd`, `level_validator.gd`, `level_solver.gd`, `level_builder.gd`, `archetypes/*.gd`. Todos `RefCounted` exceto o builder (`Node`).
3. `screens/game.tscn`: garantir `World: Node2D` como parent canônico da fase (hoje vazio — manter).
4. `components/cannon-controller/CannonController.tscn`: remover obstáculos hardcoded (viram dados); manter `Cannon`, `PowerSlider`, `FireButton`; adicionar nó `LevelLoader` (script que pede `seed/level_number` ao gerador e chama o builder). Posição do canhão vira `cannon_position` da definição (default = atual `173,523`).
5. `components/cannon/cannon.gd`: expor `get_muzzle_global_transform() -> {origin, direction}` puro (sem instanciar) para o solver reutilizar a mesma matemática; trocar `get_tree().current_scene.add_child` por parent injetável (default mantém comportamento atual para não quebrar a cena de teste).
6. `components/bullet/*`: expor constantes (`RADIUS=46.17`, `DETECTOR_RADIUS=56`) e garantir `collision_layer/mask` documentadas; shards ganham layer que não interage com solver/validador.
7. `components/hud/hud.tscn` (+ script futuro): refletir `ammo` e `Fase N` a partir da definição (hoje labels estáticos).
8. `project.godot`: fixar `physics/common/physics_ticks_per_second=60` (se ainda não estiver) e registrar `PlayBounds` como autotoload de constantes ou `ProjectSettings` custom.

`LevelBuilder` (pseudocontrato):

```text
LevelBuilder.build(world: Node2D, def: LevelDefinition):
  clear_group(world, "level_spawned")
  spawn Target em def.target
  para cada ObstacleDefinition: instantiate cena por kind (dicionário kind->PackedScene)
    set position/rotation/scale; add_to_group("level_spawned")
  configura ammo/hud/canhão
```

Geração de dados nunca importa `World`/`Node` — recebe só `RNG + config`.

---

## 13. Tratamento de falhas

| Falha | Comportamento |
|---|---|
| Candidato sem solução (solver retorna `null`) | Descarta, loga `{seed, candidato#, motivo: no_solution}`, próximo candidato com o RNG avançado. |
| Validador reprova | Descarta sem rodar o solver (economiza ms), loga `erros[]`. |
| `MAX_CANDIDATES` excedido (ex.: 40) | Usa `FALLBACK_SEEDS[dificuldade]` — lista de seeds pré-validadas (curadoria manual + teste automatizado). Nunca trava, nunca entrega fase não resolvida. |
| Solver indeterminado (timeout interno) | Trata como `null` + flag `solver_timeout=true`; conta para o limite de candidatos. |
| Config impossível (ex.: `required_ricochetes=3` com `metal_count=0`) | Erro de configuração em tempo de dev (assert + mensagem), não em runtime do jogador. Validador de config roda nos testes. |
| Versão do gerador incompatível (save antigo) | Regenera com a versão gravada se suportada; senão mapeia para fallback da dificuldade atual e avisa no log. |
| Física divergente entre plataformas | Contrato é "mesma seed, mesma versão, mesmo aparelho = mesma fase". Fallbacks garantem jogabilidade mesmo com divergência. |

---

## 14. Testes

Framework: `GUT` (ou `GdUnit4`) + testes headless (`godot --headless --path . -s`). Cobertura mínima:

- **Determinismo**: mesma seed 2× → `to_dict()` idêntico; seeds diferentes → layouts diferentes (amostra de 20 seeds).
- **Geração**: 1000 gerações sem exceção (eco do PRD), tempo médio/p95 < 300 ms em desktop (meta proxy p/ mobile).
- **Posicionamento**: nenhum AABB fora de `PlayBounds`; nenhuma sobreposição (propriedade: para 200 seeds).
- **Colisões**: cena de simulação contém os colisores esperados por tipo (metal/pedra sólidos, vidro atravessável); bullet atravessa vidro e rebate em metal (2 testes de regressão física).
- **Solucionabilidade**: para 50 seeds por faixa de dificuldade, `solve()` encontra solução e **re-simular a solução move a move atinge o alvo** (teste de ponta a ponta do `SolutionRecord`).
- **Dificuldade**: score médio cresce com `level_number`; fases 1–3 têm solução direta (`ricochetes=0`); fase 11+ exige `≥1` ricochete (conforme RN-06).
- **Seeds conhecidas**: lista dourada (`seed -> hash do layout + solução`) que quebra se o algoritmo mudar sem bump de `generator_version`.
- **Regressões de física**: travar `base_shot_speed=2000`, `power` range, massas e materiais como constantes testadas; qualquer mudança intencional exige atualizar a lista dourada + versão.

Critério de aceite da etapa solver: grade calibrada que resolve 100% das `FALLBACK_SEEDS` e ≥95% de 200 seeds aleatórias por faixa, dentro do orçamento.

---

## 15. Ordem de implementação (etapas pequenas, independentes)

> Cada etapa lista objetivo, arquivos, mudanças, dependências e **critério de conclusão (DoD)**. Nada aqui foi implementado — é a fila para a próxima fase.

### Etapa 0 — Congelar constantes e criar o Alvo
- Objetivo: base determinística + condição de vitória modelada.
- Arquivos: `project.godot` (ticks 60), `components/target/target.{tscn,gd}` (novo), `components/cannon/cannon.gd` (expor `get_muzzle_state()`, parent injetável), `components/bullet/*` (documentar layers/raios).
- DoD: cena de teste manual atinge um `Target` colocado à mão e emite `hit`; `get_muzzle_state()` retorna origem/direção usadas pelo `shoot()` (teste unitário).

### Etapa 1 — `LevelDefinition` + `DifficultyConfig` (só dados)
- Objetivo: contratos serializáveis.
- Arquivos (novos): `components/level/level_definition.gd`, `obstacle_definition.gd`, `target_definition.gd`, `solution_record.gd`, `difficulty_config.gd` (+ tabela `difficulty_table.gd`).
- DoD: `to_dict/from_dict` round-trip testado; tabela cobre fases 1–20 com bandas de score.

### Etapa 2 — Tabela de comportamento por material (sem física ainda)
- Objetivo: isolar regras que o solver usará (HP, atenuação, atravessa/rebate).
- Arquivos: `components/level/material_rules.gd` (novo; lê os valores reais: vidro `0.85` atravessa, pedra `0.85` + 2HP, metal rebote motor).
- DoD: testes de tabela para cada tipo; divergências PRD×código documentadas e resolvidas (vale o código).

### Etapa 3 — `LevelValidator` (regras baratas)
- Objetivo: reprovar rápido.
- Arquivos: `components/level/level_validator.gd` + testes.
- DoD: 100% dos casos sintéticos inválidos (fora de limites, sobreposição, alvo colado, caixa fechada) reprovados com código de erro correto; 200 defs válidas aprovadas.

### Etapa 4 — Cena de simulação + `simulate_shot` (1 tiro)
- Objetivo: provar que a simulação headless replica o jogo.
- Arquivos: `components/level/simulation_world.tscn/.gd` (novo, mínimo), `level_solver.gd` (só `simulate_shot` + predicado de término + kill-plane/timeout).
- Dependência: Etapas 0–2.
- DoD: para 10 defs manuais, `simulate_shot` acerta/erra igual ao jogo manual (comparação assistida); shards/tweens provados ausentes da simulação.

### Etapa 5 — `LevelSolver` completo (BFS multi-tiro + grade + refinamento)
- Objetivo: encontrar sequências com `ammo` limitada.
- Arquivos: `level_solver.gd` (BFS, grade, poda, early-exit, `SolutionRecord` com precisão/ricochetes).
- Dependência: Etapa 4.
- DoD: resolve 100% das fallbacks + ≥95% de amostra; registra `shots/ricochetes/solutions_found/margin`; tempo por `solve` medido e dentro da meta com a grade calibrada.

### Etapa 6 — Arquétipos + `ProceduralLevelGenerator` (sem builder)
- Objetivo: gerar candidatos com alta taxa de aprovação.
- Arquivos: `archetypes/*.gd` (6 da §9), `procedural_level_generator.gd` (RNG, loop candidato→validador→solver, fallbacks).
- Dependência: Etapas 1, 3, 5.
- DoD: determinismo por seed provado; taxa de aprovação e tempo médio reportados; `FALLBACK_SEEDS` curadas.

### Etapa 7 — `LevelBuilder/Loader` + integração de cena
- Objetivo: dados → Nodes jogáveis.
- Arquivos: `level_builder.gd`, `CannonController.tscn` (remove hardcode, adiciona loader), `screens/game.tscn` (`World` como parent), `hud` (ammo/fase), `cannon.gd` (parent do bullet = `World`).
- Dependência: Etapas 1, 6.
- DoD: mesma seed gera visual idêntico em 2 loads; jogar a `SolutionRecord` manualmente vence a fase; munição/derrota/vitória funcionam.

### Etapa 8 — Dificuldade objetiva + calibragem
- Objetivo: ligar `SolutionRecord` à `DifficultyConfig`.
- Arquivos: `difficulty_scorer.gd`, ajustes na tabela, logs de telemetria local (sem rede).
- Dependência: Etapas 5–7.
- DoD: curva de score crescente validada em 200 seeds; bandas por faixa aplicadas (rejeita fora da banda).

### Etapa 9 — Performance, async e hardening
- Objetivo: garantir 300 ms e UX de transição.
- Arquivos: orçamentos (`TIME_BUDGET_MS`), geração assíncrona na troca de fase, cache de AABBs/cena, lista dourada de seeds.
- Dependência: todas.
- DoD: benchmark 1000 gerações com p95 documentado; fallback nunca falha; sem travamento de frame (perfilado).

---

## 16. Riscos e decisões

| # | Risco / decisão | Impacto | Mitigação / decisão proposta |
|---|---|---|---|
| R1 | Simulação headless divergir do jogo (timing, `await` de 2 frames da pedra, ordem de sinais) | Solver aprova fase impossível ou reprova fase boa | Etapa 4 como prova de fidelidade; reutilizar os **scripts reais** de obstáculo na simulação; pedra modelada com os mesmos 2 `physics_frame`; lista dourada trava regressões. |
| R2 | Custo do solver estourar 300 ms em mobile | Travamento entre fases | Grade grossa+fina, early-exit, poda por estado, cena mínima, async + fallback. Calibrar com benchmark real antes de apertar a grade. |
| R3 | RNG global dos shards quebrar determinismo | Flakiness | Solver/gerador nunca usam global; shards fora da simulação; migrar shards para RNG próprio na implementação. |
| R4 | Sem alvo/munição/placar hoje — escopo cresce | Subestimativa | Etapa 0 cria o mínimo jogável antes do gerador; HUD/save completos ficam para depois do MVP do gerador. |
| R5 | PRD descreve física idealizada (reflexão perfeita, atenuações, ângulo 0–90) que o código não implementa | Plano baseado em premissa falsa | **Decisão: vale o código.** Usar `[-20,83]`, `[0.3,1.0]`, `bounce=1.0`, `0.85`; sincronizar PRD/GDD na implementação. |
| R6 | `Cannon.shoot()` adiciona bullet em `current_scene`, não em `World` | Builder/solver assumem parent errado | Decisão: parent injetável com default atual; simulação e jogo usam o mesmo parent canônico (`World`). |
| R7 | Vidro como `Area2D` (atravessável) vs. expectativa de "parede" | Validador/solver modelam errado | Documentado em §2.2/§7: vidro = atenua+remove, nunca rebate. Teste de regressão dedicado. |
| R8 | Rotação/escala arbitrárias explodem o espaço de busca | Geração lenta, validação fraca | Decisão v1: rotação ∈ `{0°, 90°}`, escala fixa por tipo. Liberar após MVP com version bump. |
| R9 | A* / RL / aprendizado parecem atraentes | Complexidade sem ganho | Decisão: amostragem + simulação + BFS limitada. Justificativa em §7.2. Sem IA/ML/runtime. |
| R10 | Mudança futura do algoritmo invalida seeds salvas | Jogador perde continuidade | `generator_version` obrigatório + fallbacks por dificuldade + teste de lista dourada. |

**Decisões que precisam de dono antes da Etapa 4:** tamanho fixo do alvo, `PlayBounds` exato (com margens e kill-plane), timeout de tiro, `MAX_CANDIDATES`, `EARLY_EXIT_COUNT` e a grade inicial — todos propostos aqui como ponto de partida, a calibrar com benchmark.

---

## Apêndice — Mapa rápido de arquivos existentes citados

`project.godot` · `screens/game.tscn` · `components/cannon-controller/CannonController.tscn` · `components/cannon-controller/cannon_controller.gd` · `components/cannon/cannon.{tscn,gd}` · `components/cannon/bullet_return_detector.gd` · `components/bullet/bullet.{tscn,gd}` · `components/obstacles/obstacle.gd` · `components/obstacles/metal/metal_obstacle.gd` · `components/obstacles/metal/metalObstacle.tscn` · `components/obstacles/stone/stone_obstacle.gd` · `components/obstacles/stone/stoneObstacle.tscn` · `components/obstacles/glass/glass_obstacle.gd` · `components/obstacles/glass/glassObstacle.tscn` · `components/obstacles/shard.gd` · `components/obstacles/stone/stone_shard.gd` · `components/obstacles/glass/glass_shard.gd` · `components/power-slider/power_slider.gd` · `components/power-slider/powerSlider.tscn` · `components/hud/hud.tscn` · `components/fire-button/fireButton.tscn` · `docs/PRD.md` · `docs/GDD.md`.
