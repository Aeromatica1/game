# Passageiros (NPCs)

- **Fluxo:** propriedade `densidade` (1–10) do nó `Mundo/Passageiros` (Inspector), ou
  `get_tree().call_group("passageiros", "definir_densidade", 7)`.
  Em jogo: PageUp / PageDown.
- **Sprites:** vêm de `assets/airport_npcs_improved_4x/.../spritesheets` (PNGs 32x32, 4 colunas x 8 linhas:
  andar baixo/cima/esquerda/direita, depois correr). O elenco e os pesos de sorteio ficam em
  `personagem_sprites.gd` (`PERSONAGENS`). Passageiros: passenger_m/f e tourist_m/f (50% de cada sexo).
  `businessman_m` / `businesswoman_f` são do jogador (`personagem` em player.gd).
- **Funcionários andando:** além dos que ficam no posto, alguns perambulam (employee 35%, staff 30%,
  service 20%, pilot 15%; metade homens, metade mulheres). Não sentam. A quantidade é
  `FRACAO_FUNCIONARIOS` (15% dos passageiros que andam, mínimo 1) em `passageiros_manager.gd`.
- **Assentos:** achados automaticamente (fileiras das poltronas e bancos, 1 lugar a cada
  `assento_largura` px). Ajuste `assento_largura` / `assento_deslocamento` conforme o resultado em jogo.
  Para um assento virar outra direção, ponha `direcao_assento` (metadata) no Sprite2D da fileira.
- O nó `Mundo` agora tem `y_sort_enabled`, para NPCs e jogador se ordenarem pela posição Y.
- O jogador passou a colidir com NPCs (`collision_mask = 9` em player.tscn).

## Funcionários e tela de questões
- `npc/funcionario.tscn`: atendente parado no posto. Perto dele aparece "E - Falar"; E (ou Enter) abre a
  tela de questão (`questoes/tela_questao.tscn`). Já há 4 no mapa (check-in, informações, companhia, pesagem);
  duplique o nó `Func_*` em `Mundo` e mude `contexto`, `nome_funcionario`, `cargo`, `personagem`, `direcao`.
  Se algum aparecer fora do lugar, só arraste o nó.
- Perguntas/gabarito: implemente `proxima_questao(contexto)` em `questoes/banco_questoes.gd`
  (formato do dicionário está no topo do arquivo). Sinal `resposta_escolhida` avisa o que o jogador marcou.

## Cabeça e colisão
- NPCs, funcionários e jogador são desenhados em duas partes (corpo e cabeça); a cabeça tem z_index maior,
  então nunca some atrás do corpo de outro personagem. A linha de corte é `linha_cabeca` (padrão 20 px).

## Você decide onde cada funcionário nasce e o que ele faz
- **Onde:** os funcionários são nós normais em `Mundo` (`Func_*`). Arraste-os, duplique (Ctrl+D) ou apague
  à vontade, ou instancie `npc/funcionario.tscn` onde quiser.
- **O que faz:** no Inspector do funcionário, `acao` = QUESTAO (tela de pergunta) ou MINIGAME.
  Em MINIGAME, arraste a cena em `minigame` (ex.: `minigames/minesweeper/game.tscn`,
  `minigames/block_blast/Main.tscn`). O minigame abre por cima do mapa e fecha com Esc/botão.
  `texto_dica` troca o "E - Falar". Hoje o `Func_Pesagem` leva ao Campo Minado, como exemplo.
