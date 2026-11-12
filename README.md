# ✈️ Aeromática

> Administre um aeroporto usando a matemática como aliada.

**Aeromática** é um jogo de gestão de aeroportos desenvolvido como **Projeto Interdisciplinar de 2026**, no curso de Desenvolvimento de Sistemas (turma 331 DS, período vespertino).

O nome nasce da junção de **"Aeroporto"** com **"Matemática"**, os dois temas do jogo, e funciona como um trocadilho com **"Aeronáutica"**, a ciência da navegação aérea.

---

## 📦 O que há neste repositório

- **Jogo**: desenvolvido na **Godot Engine**.
- **Site**: desenvolvido com **HTML, CSS e JavaScript**.

## 🛠️ Tecnologias

As principais tecnologias utilizadas no projeto foram **Godot** e **Spring Boot**.

| Parte | Tecnologia |
|-------|------------|
| Jogo  | Godot Engine |
| Site  | HTML, CSS e JavaScript |

Outras ferramentas que fizeram parte do desenvolvimento: C++, SQLite, Docker, LaTeX, FL Studio e Visual Studio Code.

---

## 🎮 Panorama geral do jogo

Em Aeromática, o jogador assume a missão de **administrar um aeroporto em todas as suas partes**.

A ideia central é que a **matemática atue como principal aliada** no processo. Ela também está presente nas tarefas que o jogador resolve para ganhar **pontos de experiência, dinheiro e outros benefícios** para o próprio aeroporto.

Os conceitos matemáticos ficam **mais difíceis conforme o jogador evolui o estabelecimento**. As tarefas têm **prazo de validade**, e o tempo disponível também aumenta conforme a dificuldade.

### Estilo visual

- Pixel art
- Perspectiva top-down
- Paleta de cores suave

## 📈 Sistema de evolução

O aeroporto evolui em **4 níveis**, e cada um libera novos destinos e recursos.

| Nível | Requisitos | O que desbloqueia |
|-------|-----------|-------------------|
| **1** | Ponto de partida: 3 portões de embarque, 3 guichês de venda de passagens, 3 guichês de check-in e aeronaves básicas | Conexão com 3 cidades brasileiras, à escolha do jogador |
| **2** | 6 portões de embarque (3 com qualidade nível 2) e ao menos 1 aeronave intermediária | Espaços para comércio (aluguel para empresas, como nova fonte de renda) e todas as capitais brasileiras como destino |
| **3** | 10 portões (5 com nível 3 e 3 com nível 2), 3 pontos de comércio e 3 aeronaves intermediárias | Viagens internacionais (até 3 cidades à escolha) |
| **4** | 15 portões (6 com nível 3 e 2 com nível 2), 5 pontos de comércio, 2 aeronaves avançadas e 5 intermediárias | Todos os destinos internacionais do sistema |

Em todos os níveis, o jogador decide como distribuir os destinos entre os espaços disponíveis.

### Sistema de upgrades

O jogador investe em **conforto, tecnologia e qualidade** para os passageiros. Ao pagar o valor do upgrade, o espaço é modificado para aumentar a satisfação dos clientes e, consequentemente, a qualidade do aeroporto.

### Sistema de tarefas

Ao longo do jogo, o jogador resolve tarefas ligadas à gestão do aeroporto que envolvem **problemas matemáticos**. Elas servem para conquistar experiência, dinheiro e benefícios.

---

## 🧮 A matemática no jogo

A matemática aparece em dois domínios: **minigames** e **tarefas**.

- **Minigames:** matemática mais "fácil" ou intuitiva para o jogador, porém mais "difícil" para o computador (matrizes, filas, pilhas, listas de adjacência e lógica booleana).
- **Tarefas:** matemática mais "simples" para o computador, porém mais "difícil" para o jogador (funções, equações, progressões, combinatória e probabilidade).

### 🕹️ Minigames

| Minigame | Função no jogo | Matemática envolvida |
|----------|----------------|----------------------|
| **Tetris** | Organização de malas | Matrizes (o tabuleiro guarda posições vazias ou ocupadas), lógica booleana para detectar colisões, varredura da matriz para remover linhas completas, geometria e organização espacial |
| **Encanador** | Gerar rotas de esteiras | Grafos (peças como nós e conexões como caminhos), restrições de rotação, algoritmos de busca como DFS e backtracking |
| **Campo Minado** | Mapear pontos de inspeção | Lógica booleana, matrizes, grid graph (teoria dos grafos) e flood fill |

Na **gestão de malas**, o jogo ainda usa matrizes, grafos, DFS e BFS. Em um dos exemplos, o jogador traça a rota correta de um labirinto para as malas chegarem aos aviões certos no menor tempo possível e, se uma esteira falhar, precisa redesenhar a rota.

### 📝 Tarefas: níveis de dificuldade

| Nível | Conteúdo |
|-------|----------|
| **1** | Operações aritméticas básicas, função afim, geometria plana |
| **2** | Cálculos algébricos, sistemas de equações |
| **3** | Função quadrática, progressão aritmética e geométrica |
| **4** | Raciocínio lógico, análise combinatória, probabilidade |

As fórmulas do sistema são usadas em todos os níveis, com dificuldade maior nos níveis mais adiantes.

### Exemplos de tarefas

**Nível 1 (função afim):** um aeroporto cobra R$ 15 por passageiro, mais uma tarifa operacional fixa de R$ 5.000. Qual função representa o custo total para *x* passageiros?
→ `f(x) = 15x + 5000`

**Nível 2 (sistema de equações):** um aeroporto recebeu 120 voos entre nacionais (100 passageiros cada) e internacionais (200 passageiros cada), com 18.000 passageiros no total. Quantos voos de cada tipo?
→ `100x + 200y = 18000` e `x + y = 120`, logo **60 nacionais e 60 internacionais**.

**Nível 3 (função quadrática):** o lucro de uma rota é `L(x) = -2x² + 400x - 150`, onde *x* é o preço da passagem. Qual valor de *x* maximiza o lucro?
→ `Xv = -b / 2a = 100`

**Nível 4 (combinatória):** em um voo de 30 assentos, restam 6 livres na última fileira. Um casal comprou passagens de última hora e, no mesmo avião, uma mãe e uma criança devem ficar lado a lado. De quantas formas os 4 passageiros podem ser reorganizados nesses 6 assentos?
→ `5 · 12 · 2 = 120`

### Fórmulas

- **Preço do aluguel:** `A = M · V · Fp · Na`
  *(A = aluguel mensal, M = metragem em m², V = valor base por m² em R$/m², Fp = fator de fluxo de passageiros de 1 a 10, Na = nível do aeroporto de 1 a 4)*
- **Preço das passagens:** `P = (S · C · P + M · NQ) / NP`
  *(S = distância em km, C = consumo médio de combustível em L/km, P = preço do combustível em R$/L, M = custo de manutenção em R$, NQ = nível de qualidade do avião de 1 a 5, NP = número de passageiros)*
- **Custo de expansão das pistas:** `Custo = C · l · M`
  *(C = comprimento em km, l = largura em km, M = custo por m² em R$/m²)*
- **Custo das aeronaves:** `V = Cp · T + 1000 · Vm · B`
  *(V = valor da aeronave em R$, Cp = número de assentos, T = valor por assento em R$, Vm = velocidade média em km/h, B = bônus tecnológico de 1 a 100)*

---

## 🗓️ Cronograma

O planejamento foi organizado de março a julho de 2026:

- **Pré-projeto:** definição do tema e escopo, narrativa, mecânicas e design, divisão de tarefas, definição das tecnologias e identidade visual (paleta e arte).
- **Arte e design:** UI/HUD do jogo, design de personagens, design dos cenários, sprites animados e ícones.

---

## 👥 Equipe

- Kenji Ogawa Morimoto
- Levi Alves Sant'Ana
- Lucas Pereira Cardoso
- Raphael Vicente de Oliveira
- Valter de Sales Santana Junior

**Desenvolvimento de Sistemas Vespertino — 331 DS**

---

## 🔗 Links

- Repositório: https://github.com/Aeromatica1