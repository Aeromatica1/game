# Passageiros (NPCs)

- **Fluxo:** propriedade `densidade` (1–10) do nó `Mundo/Passageiros` (Inspector), ou
  `get_tree().call_group("passageiros", "definir_densidade", 7)`.
  Em jogo: PageUp / PageDown. F3 = mostra assentos, F4 = mostra a grade andável.
- **Sprites:** sem configurar nada, usa o sprite do jogador com cores variadas.
  Para ter personagens próprios, coloque spritesheets (mesmo layout 6x4, células 28x28)
  em `texturas_npc` do nó Passageiros.
- **Assentos:** achados automaticamente (fileiras das poltronas e bancos, 1 lugar a cada
  `assento_largura` px). Ajuste `assento_largura` / `assento_deslocamento` olhando o F3.
  Para um assento virar outra direção, ponha `direcao_assento` (metadata) no Sprite2D da fileira.
- O nó `Mundo` agora tem `y_sort_enabled`, para NPCs e jogador se ordenarem pela posição Y.
- O jogador passou a colidir com NPCs (`collision_mask = 9` em player.tscn).

## Funcionários e tela de questões
- `npc/funcionario.tscn`: atendente parado no posto. Perto dele aparece "E - Falar"; E (ou Enter) abre a
  tela de questão (`questoes/tela_questao.tscn`). Já há 4 no mapa (check-in, informações, companhia, pesagem);
  duplique o nó `Func_*` em `Mundo` e mude `contexto`, `nome_funcionario`, `cargo`, `matiz`, `direcao`.
  Se algum aparecer fora do lugar, só arraste o nó.
- Perguntas/gabarito: implemente `proxima_questao(contexto)` em `questoes/banco_questoes.gd`
  (formato do dicionário está no topo do arquivo). Sinal `resposta_escolhida` avisa o que o jogador marcou.

## Cabeça e colisão
- NPCs, funcionários e jogador são desenhados em duas partes (corpo e cabeça); a cabeça tem z_index maior,
  então nunca some atrás do corpo de outro personagem. A linha de corte é `linha_cabeca` (padrão 19 px).

## Aluguel de áreas (sinal de "+")
- Os 5 sprites `Novaloja*` em `Mundo/estabelecimentos` usam `aluguel/espaco_aluguel.gd`. Perto deles aparece
  "T / clique - Alugar espaço"; apertar **T** ou **clicar** no "+" abre `aluguel/tela_escolha_area.gd`
  (lanchonete, livraria, cafeteria, loja; teclas 1-4 ou mouse) e depois a `tela_questao` (só o espaço em branco).
- Sinal `area_alugada(tipo, acertou)` no espaço avisa o fim do fluxo — é o ponto para trocar o "+" pela loja.
- Ícones das áreas: `assets/areas/`. A "Loja" ainda não tem ícone (edite `OPCOES` em `tela_escolha_area.gd`).
- Ajuste a distância de ativação com `folga_lateral/cima/baixo` no Inspector de cada `Novaloja`.
