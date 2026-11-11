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

# ------------------------- Saves -------------------------
## Lista os até 3 saves com um resumo do aeroporto.
func listar_saves() -> Dictionary:
	return await Supabase.request(
		S + "save_slot?select=id,numero_slot,data_modificado,"
		+ "aeroporto(id,nivel_aeroporto_id,dinheiro,fluxo_passageiros)&order=numero_slot")

## Cria o save + aeroporto inicial. Retorna o id (uuid) do aeroporto em `data`.
func criar_save(numero_slot: int) -> Dictionary:
	return await Supabase.rpc("criar_save_slot", {"p_numero": numero_slot})

func apagar_save(save_slot_id: String) -> Dictionary:
	return await Supabase.request(S + "save_slot?id=eq." + Supabase.q(save_slot_id),
		HTTPClient.METHOD_DELETE)

# ------------------------- Carregar progresso -------------------------
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
func alugar_espaco(aeroporto_id: String, tipo_aluguel_id: int, x: float, y: float) -> Dictionary:
	return await Supabase.rpc("alugar_espaco", {
		"p_aeroporto": aeroporto_id, "p_tipo": tipo_aluguel_id, "p_x": x, "p_y": y})

## `data` = true/false (acertou). O servidor valida e paga a recompensa.
func responder_questao(aeroporto_id: String, questao_id: int, alternativa_id: int) -> Dictionary:
	return await Supabase.rpc("responder_questao", {
		"p_aeroporto": aeroporto_id, "p_questao": questao_id, "p_alternativa": alternativa_id})

func concluir_minigame(aeroporto_id: String, tipo_minigame_id: int, score: float) -> Dictionary:
	return await Supabase.rpc("concluir_minigame", {
		"p_aeroporto": aeroporto_id, "p_tipo": tipo_minigame_id, "p_score": score})

## `data` = novo nível.
func evoluir_aeroporto(aeroporto_id: String) -> Dictionary:
	return await Supabase.rpc("evoluir_aeroporto", {"p_aeroporto": aeroporto_id})
