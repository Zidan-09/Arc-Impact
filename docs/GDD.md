## 1. Visão Geral do Projeto

* **Nome:** *Arc-Impact*
* **Gênero:** Physics-Based Puzzle / Casual Shooter
* **Plataforma Target:** Mobile (Android / iOS) e PC (Web / Steam)
* **Estilo Visual:** Minimalista Arcade / Cyberpunk Neon (Tons de roxo e lilás)

* **Público-Alvo:** Jogadores casuais e fãs de jogos de puzzle baseados em física (*Angry Birds*, *Peggle*, *Cut the Rope*).

---

## 2. Conceito Principal (*High Concept*)

Um jogo de puzzle e precisão em 2D onde o jogador controla um canhão futurista para acertar um alvo lateral em cenários neon gerados de forma procedural. Cada fase possui obstáculos com propriedades de materiais únicas (frágil, equilibrado e resistente) e uma quantidade limitada de disparos.

---

## 3. Loop Principal do Jogo (*Core Loop*)

```
[ Análise da Fase ] ──> [ Ajuste de Mira/Força ] ──> [ Disparo ]
        ▲                                                │
        │                                                ▼
[ Tentar Novamente ] <── [ Derrota ] ◄── [ Checagem de Impacto ] ──► [ Vitória ] ──> [ Próxima Fase ]

```

---

## 4. Mecânicas de Gameplay

### 4.1. Controle do Canhão

* **Posicionamento:** Fixo no canto esquerdo da tela.
* **Ângulo de Disparo:** Variável entre $0^\circ$ e $90^\circ$.
* **Potência/Força:** Barra de carga ao segurar/arrastar o botão de disparo.
* **Linha de Trajetória:** Exibe os primeiros metros do arco parabólico para auxiliar a precisão.

### 4.2. Munição e Condições

* **Limite de Tiros:** Cada fase sorteia uma quantidade limite de munições (ex: 1 a 4 disparos).

* **Vitória:** O projétil atinge o alvo direto ou via ricochete.

* **Derrota:** A munição acaba sem que o alvo tenha sido atingido.

---

## 5. Sistema de Materiais (Física dos Obstáculos)

Os obstáculos não flutuam; estão sempre conectados por vigas ou suportes ao cenário.

| Material | Resistência (HP) | Efeito ao Impacto | Visual / Feedback |
| --- | --- | --- | --- |
| **Frágil** | 1 Acerto | O projétil destrói o bloco e atravessa com leve perda de velocidade. | Partículas neon se espalhando; som de cristal quebrando. |
| **Equilibrado** | 2 Acertos | **1º Tiro:** Sofre dano físico. **2º Tiro:** É destruído. | Textura ganha rachaduras neon visíveis no 1º impacto. |
| **Resistente** | Indestrutível | O projétil **ricocheteia** preservando a força com base no ângulo de incidência. | Efeito de faíscas neon no ponto de impacto; som metálico. |
| **Interagível** | Indestrutível mas mutável | Executa uma ação | Botão aperta, porta abre, projétil brilha...

### 5.1. Materiais Interagíveis

Os materiais interagíveis são mecanismos que geram mais possibilidade de fases para o jogador avançar.

Exemplos de interagíveis:
1. Botão que ao ser atingido realiza alguma ação
2. Portão que se abre
3. Levitação que adiciona um impulso ao projétil

---

## 6. Geração Procedural de Fases (*Level Design*)

O jogo não possui um fim; utiliza um algoritmo de geração por regras para garantir jogabilidade infinita:

1. **Sorteio do Alvo:** Define a posição do alvo na extremidade direita da tela (fixo na parede ou em suportes).

2. **Criação da Rota Solução:** O sistema gera primeiro a trajetória matemática vitoriosa (podendo incluir 1 ou mais ricochetes).

3. **Injeção de Obstáculos:** Insere blocos frágeis, equilibrados e resistentes ao redor do caminho para criar o desafio.

4. **Cálculo da Dificuldade ($D$):**
* *Fases Iniciais (1 a 10):* Trajetórias diretas com poucos blocos frágeis.
* *Fases Avançadas (11+):* Paredes resistentes bloqueando o tiro direto, forçando o uso de ricochetes múltiplos em ângulos precisos.

---

## 7. Direção de Arte e Audio

* **Paleta de Cores:** Fundo escuro (roxo profundo / azul-noite) com elementos brilhantes em lilás, magenta e ciano.

* **UI Minimalista:**
* Canto superior: Número da Fase, Pontuação e Ícones de Tiros Restantes.


* Canto inferior: Medidores de Ângulo e Potência.

* **Audio:**
* Trilha sonora estilo *Synthwave / Retrowave* suave e hipnótica.
* Efeitos sonoros synth/arcade para disparos, ricochetes e destruição de blocos.

---

## 8. Sistema de Metagame e Personalização

Moedas virtuais são obtidas ao passar de fases para desbloquear itens cosméticos:

* **Skins de Canhões:** Modelos neon, futuristas, retrô arcade.

* **Efeitos de Munição:** Rastro de luz (*trails*), partículas de estrelas, pulso laser.

* **Temas de Interface:** Variações das cores neon do HUD (Rosa/Lilás, Azul/Ciano, Verde/Neon).