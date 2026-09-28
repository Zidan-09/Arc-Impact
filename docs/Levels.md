# Regras para Geração de Fases

Este documento define as regras e restrições que devem ser respeitadas pelo gerador procedural de fases.

As fases devem utilizar as fases desenhadas manualmente em `guide/` como **referência visual e estrutural**. Os arquivos em `guide/` representam exemplos de como uma fase pode ser construída, mas não devem ser reproduzidos literalmente. O gerador deve utilizar os mesmos princípios para criar fases novas e únicas.

---

## 1. Estrutura geral da fase

Cada fase deve possuir, no mínimo:

* `Floor`
* `Cannon`
* `Target`
* `Obstacles`
* `Structures`, quando necessárias para conectar os `Obstacles`

A composição final deve formar uma estrutura coerente e jogável, evitando elementos simplesmente posicionados de forma aleatória.

---

## 2. Floor

O `Floor` é a base estrutural da fase e deve obedecer às seguintes regras:

* O `Floor` deve cobrir todo o piso da fase.
* O `Floor` deve sempre fazer sentido com a posição do `Cannon`.
* O `Floor` deve sempre encostar diretamente na base do `Cannon`.
* O `Floor` pode possuir diferentes alturas e formatos.
* Caso o `Cannon` esteja em uma posição elevada, o `Floor` deve ser construído de forma que:

  1. suba até alcançar a altura do `Cannon`;
  2. forneça sustentação à base do `Cannon`;
  3. retorne posteriormente ao plano normal do piso.

O `Floor` não deve deixar o `Cannon` visualmente ou fisicamente flutuando.

### Exemplo conceitual

```text
                    CANNON
                      █
                 █████████
                /
               /
              /
_____________/________________
             FLOOR
```

A elevação do `Floor` deve fazer parte do desenho da fase, e não ser apenas uma correção para posicionar o `Cannon`.

---

## 3. Cannon

O `Cannon` deve respeitar as seguintes regras:

* O `Cannon` deve estar sempre no lado esquerdo da tela.
* O `Cannon` pode estar em qualquer altura da tela.
* A posição vertical do `Cannon` deve ser determinada pelo desenho e desafio da fase.
* O `Cannon` deve estar sempre apoiado pelo `Floor`.

A posição elevada do `Cannon` pode ser utilizada para criar diferentes geometrias de fase e ângulos de disparo.

---

## 4. Target

O `Target` deve seguir estas regras:

* O `Target` deve estar normalmente no lado direito da tela.
* O `Target` pode estar em qualquer altura da tela.
* O `Target` pode ser rotacionado.
* A rotação e a posição do `Target` devem ser utilizadas quando contribuírem para o desenho ou desafio da fase.
* O `Target` pode fugir da regra de estar no lado direito **quando o desenho da fase exigir explicitamente um desafio especial**.

A posição do `Target` deve incentivar o jogador a utilizar as propriedades físicas e mecânicas da fase, e não simplesmente exigir um disparo direto.

---

## 5. Obstacles

Os `Obstacles` são os principais elementos responsáveis pela construção dos desafios.

### Conectividade

Os `Obstacles` devem sempre fazer parte de uma estrutura fisicamente coerente:

* Todo `Obstacle` deve estar conectado ao `Floor`, direta ou indiretamente.
* Os `Obstacles` devem estar conectados entre si.
* Um `Obstacle` não deve aparecer isolado ou simplesmente flutuando no cenário.
* A conexão entre `Obstacles` deve utilizar `Structures` quando necessário.

Conceitualmente:

```text
Obstacle ── Structure ── Obstacle
    │                         │
    └──── Structure ──────────┘
              │
            Floor
```

As `Structures` devem servir como elementos estruturais que conectam e sustentam os `Obstacles`, fazendo com que a construção tenha coerência física e visual.

---

## 6. Quantidade e composição dos Obstacles

As fases devem possuir um número considerável de `Obstacles`.

O objetivo não é simplesmente aumentar a quantidade de objetos, mas utilizar os `Obstacles` para criar **estruturas e desenhos únicos em cada fase**.

O gerador deve evitar:

* Distribuição aleatória sem propósito.
* Repetição da mesma estrutura em várias fases.
* Grandes espaços vazios sem função.
* Obstáculos isolados.
* Estruturas visualmente simples quando houver espaço para criar um desafio mais elaborado.

Os `Obstacles` devem formar construções reconhecíveis e diferentes entre si.

---

## 7. Aproveitamento das mecânicas dos Obstacles

A geração das fases deve considerar as propriedades específicas dos `Obstacles`.

O desenho da fase deve aproveitar ao máximo as mecânicas disponíveis, especialmente:

* **Quebrar** — estruturas que podem ser destruídas pelo impacto.
* **Desgastar** — estruturas que podem sofrer múltiplos impactos antes de serem destruídas.
* **Ricochetear** — superfícies capazes de alterar a trajetória do projétil.

O posicionamento dos `Obstacles` deve criar situações nas quais essas mecânicas tenham uma função real no desafio.

### Exemplos conceituais

Uma fase pode utilizar:

```text
Cannon → Obstáculo quebrável → Target
```

para exigir a destruição de uma barreira.

Outra pode utilizar:

```text
          ┌───────────┐
Cannon →  │ Ricochete │
          └─────┬─────┘
                │
                ↓
              Target
```

para exigir que o jogador utilize o ricochete.

Também podem existir combinações:

```text
Cannon
   \
    \       [Desgastável]
     \      ███████████
      \    /
       \  / [Quebrável]
        \/  █████████
        /\       \
       /  \       \ [Ricochete]
      /    \       █████
     /      \         \
   Floor    Structures  Target
```

O objetivo é que a geometria da fase faça o jogador interagir com essas mecânicas de maneira natural.

---

## 8. Desenho da fase

Cada fase deve ser tratada como uma composição única, e não como um conjunto de objetos distribuídos aleatoriamente.

O gerador deve considerar:

* posição do `Cannon`;
* posição e rotação do `Target`;
* formato do `Floor`;
* quantidade e disposição dos `Obstacles`;
* conexões entre `Obstacles`;
* uso de `Structures`;
* possíveis caminhos do projétil;
* oportunidades de quebrar estruturas;
* oportunidades de desgastar estruturas;
* oportunidades de utilizar ricochetes.

A composição deve resultar em uma fase visualmente distinta das demais.

---

## 9. Uso dos arquivos em `guide/`

Os arquivos presentes em `guide/` são referências criadas manualmente para demonstrar como as fases devem ser construídas.

O gerador deve analisar essas fases para compreender:

* proporções;
* organização dos elementos;
* relação entre `Floor`, `Cannon`, `Target` e `Obstacles`;
* utilização de `Structures`;
* densidade de obstáculos;
* composição visual;
* criação de desafios;
* utilização das mecânicas físicas.

As fases de `guide/` **não devem ser copiadas ou reproduzidas literalmente**.

Elas devem servir como referência para a criação de novas composições que mantenham os mesmos princípios, mas apresentem desenhos e desafios diferentes.

---

## 10. Princípio principal

A geração procedural deve priorizar:

> **Uma fase deve parecer uma construção intencional, não uma coleção aleatória de objetos.**

Cada elemento deve possuir uma razão para estar onde está.

O `Floor` deve sustentar a construção.
As `Structures` devem conectar os elementos.
Os `Obstacles` devem formar o desenho e o desafio.
O `Cannon` deve estar integrado ao terreno.
O `Target` deve participar da composição.
E as mecânicas de quebrar, desgastar e ricochetear devem ser utilizadas para tornar cada fase interessante de jogar.
