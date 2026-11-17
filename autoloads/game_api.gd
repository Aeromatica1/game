extends Node
## Autoload "GameApi": operações do Aeromática sobre o Supabase.
## Todas são assíncronas e retornam { ok, code, data, error } (use `await`).
##
## Leitura  -> SELECT direto (protegido por RLS).
## Escrita  -> sempre RPC (o cliente não altera dinheiro/progresso diretamente).

const S := "/rest/v1/"

# ------------------------- Catálogos (somente leitura) -------------------------
func get_niveis() -> Dictionary:
	return await Supabase.request(S + "nivel_aeroporto?select=*&order=id")

func get_tipos_aluguel() -> Dictionary:
	return await Supabase.request(S + "tipo_aluguel?select=*&order=nivel_minimo,preco")

func get_tipos_minigame() -> Dictionary:
	return await Supabase.request(S + "tipo_minigame?select=*")

## Questões de um nível com as 4 alternativas embutidas.
## O servidor NÃO expõe `eh_correta`; embaralhe `alternativa` no cliente (shuffle()).
func get_questoes(nivel: int) -> Dictionary:
	return await Supabase.request(
		S + "questao?select=id,nivel,enunciado,alternativa(id,enunciado)&nivel=eq.%d&order=id" % nivel)

## Linha de `profiles` (id, username, created_at) do usuário logado.
func get_perfil(user_id: String) -> Dictionary:
	return await Supabase.request(S + "profiles?select=*&id=eq." + Supabase.q(user_id))

# ------------------------- Saves -------------------------
## Lista os até 3 saves com o aeroporto embutido (todas as colunas).
func listar_saves() -> Dictionary:
	return await Supabase.request(
		S + "save_slot?select=*,aeroporto(*)&order=numero_slot")

## Cria o save + aeroporto inicial. Retorna o id (uuid) do aeroporto em `data`.
func criar_save(numero_slot: int) -> Dictionary:
	return await Supabase.call_rpc("criar_save_slot", {"p_numero": numero_slot})

## Apaga o save. Com `return=representation`, `data` traz as linhas removidas:
## lista vazia = nada foi apagado (id inexistente ou RLS bloqueou).
func apagar_save(save_slot_id: String) -> Dictionary:
	return await Supabase.request(S + "save_slot?id=eq." + Supabase.q(save_slot_id),
		HTTPClient.METHOD_DELETE, null, PackedStringArray(["Prefer: return=representation"]))

## Saves com TUDO embutido numa única requisição: aeroporto(*) + respostas, aluguéis e minigames.
## (Antes eram 2 etapas em sequência: saves e, depois, os detalhes de cada aeroporto.)
func listar_saves_completo() -> Dictionary:
	return await Supabase.request(
		S + "save_slot?select=*,aeroporto(*,aeroporto_resposta(*),aluguel_localizacao(*),minigame_aeroporto(*))&order=numero_slot")

# Versões "em lote" (vários aeroportos numa requisição) para o resumo da tela de saves.
func _in_ids(ids: Array) -> String:
	var partes: PackedStringArray = []
	for i in ids:
		partes.append(Supabase.q(i))
	return "in.(" + ",".join(partes) + ")"

func get_respostas_de(aeroporto_ids: Array) -> Dictionary:
	return await Supabase.request(
		S + "aeroporto_resposta?select=*&aeroporto_id=" + _in_ids(aeroporto_ids))

func get_alugueis_de(aeroporto_ids: Array) -> Dictionary:
	return await Supabase.request(
		S + "aluguel_localizacao?select=*&aeroporto_id=" + _in_ids(aeroporto_ids))

func get_minigames_de(aeroporto_ids: Array) -> Dictionary:
	return await Supabase.request(
		S + "minigame_aeroporto?select=*&aeroporto_id=" + _in_ids(aeroporto_ids))

# ------------------------- Carregar progresso -------------------------
## UMA requisição com tudo: aeroporto, níveis, tipos, aluguéis, minigames,
## questões (sem a resposta correta) e ids das questões já concluídas.
func carregar_jogo(aeroporto_id: String) -> Dictionary:
	return await Supabase.call_rpc("carregar_jogo", {"p_aeroporto": aeroporto_id})

func get_aeroporto(aeroporto_id: String) -> Dictionary:
	return await Supabase.request(S + "aeroporto?select=*&id=eq." + Supabase.q(aeroporto_id))

func get_alugueis(aeroporto_id: String) -> Dictionary:
	return await Supabase.request(
		S + "aluguel_localizacao?select=*,tipo_aluguel(descricao,renda)&aeroporto_id=eq." + Supabase.q(aeroporto_id))

func get_minigames(aeroporto_id: String) -> Dictionary:
	return await Supabase.request(
		S + "minigame_aeroporto?select=*&aeroporto_id=eq." + Supabase.q(aeroporto_id))

## Ids das questões já respondidas (para não repetir e contar acertos).
func get_respostas(aeroporto_id: String) -> Dictionary:
	return await Supabase.request(
		S + "aeroporto_resposta?select=questao_id,acertou&aeroporto_id=eq." + Supabase.q(aeroporto_id))

# ------------------------- Ações (RPC) -------------------------
## Aluga a área `numero_area` (1 a 27, o número do nó AreaAluguelN no mapa).
## Requer a função do banco em sql/alugar_espaco.sql (p_aeroporto, p_tipo, p_area).
func alugar_espaco(aeroporto_id: String, tipo_aluguel_id: int, numero_area: int) -> Dictionary:
	return await Supabase.call_rpc("alugar_espaco", {
		"p_aeroporto": aeroporto_id, "p_tipo": int(tipo_aluguel_id), "p_area": int(numero_area)})


## Valida a resposta NO SERVIDOR.
## `data` = { acertou: bool, recompensa: float, dinheiro: float, explicacao: String|null }
func responder_questao(aeroporto_id: String, questao_id: int, alternativa_id: int) -> Dictionary:
	return await Supabase.call_rpc("responder_questao", {
		"p_aeroporto": aeroporto_id, "p_questao": int(questao_id), "p_alternativa": int(alternativa_id)})

## Game over: zera nível, dinheiro, respostas e aluguéis do save. Requer banco/reiniciar_aeroporto.sql.
func reiniciar_aeroporto(aeroporto_id: String) -> Dictionary:
	return await Supabase.call_rpc("reiniciar_aeroporto", {"p_aeroporto": aeroporto_id})

func concluir_minigame(aeroporto_id: String, tipo_minigame_id: int, score: float) -> Dictionary:
	return await Supabase.call_rpc("concluir_minigame", {
		"p_aeroporto": aeroporto_id, "p_tipo": int(tipo_minigame_id), "p_score": score})

## `data` = novo nível.
func evoluir_aeroporto(aeroporto_id: String) -> Dictionary:
	return await Supabase.call_rpc("evoluir_aeroporto", {"p_aeroporto": aeroporto_id})
