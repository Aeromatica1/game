# Airport NPCs — sprites baseados na imagem original

Este pacote usa os mesmos 10 personagens recortados diretamente da imagem de referência enviada: Pilot, Employee, Passenger, Businessman, Tourist, Staff, Passenger, Businesswoman, Tourist e Service.

## Especificações
- Cada célula: **32×32 px**, PNG RGBA com transparência.
- Cada personagem: spritesheet individual de **128×256 px** (4 frames por linha × 8 linhas).
- 4 direções: `down`, `up`, `left`, `right`.
- 4 frames de caminhada e 4 frames de corrida por direção.
- Total: **10 personagens × 8 animações × 4 frames = 320 frames**.

## Ordem das linhas
1. `walk_down`
2. `walk_up`
3. `walk_left`
4. `walk_right`
5. `run_down`
6. `run_up`
7. `run_left`
8. `run_right`

Dentro de cada linha, os quatro frames são lidos da esquerda para a direita.

## Importação
**Unity:** importe cada PNG com Texture Type `Sprite (2D and UI)`, Sprite Mode `Multiple`, Filter Mode `Point (no filter)` e Compression `None`; use Grid by Cell Size de 32×32.

**Godot:** carregue o PNG em `SpriteFrames`/`AtlasTexture`, defina região de 32×32 e selecione os quatro quadros de cada linha para a animação.

**Pygame:** cada frame pode ser obtido com `sheet.subsurface((frame * 32, row * 32, 32, 32))`.

## Observação sobre o movimento
As imagens base foram recortadas da referência original para preservar os personagens. Os ciclos foram construídos por deslocamentos pequenos de braços, pernas e corpo; portanto, são animações simples derivadas das poses estáticas, não redesenhos completos de cada articulação.
