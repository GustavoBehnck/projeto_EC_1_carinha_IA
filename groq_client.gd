class_name GroqClient
extends Node

const API_URL = "https://api.groq.com/openai/v1/chat/completions"
var api_key: String = ""
var conversation_history: Array = [] # Armazena o histórico de mensagens da conversa

func _init() -> void:
	load_token()

func load_token() -> void:
	var path = "res://.groq_token"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		api_key = file.get_as_text().strip_edges()
		file.close()

func ask_groq(prompt: String) -> String:
	# Adiciona a nova mensagem do usuário ao histórico
	conversation_history.append({"role": "user", "content": "responda prevemente: \n" + prompt})

	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	var payload = {
		"model": "openai/gpt-oss-20b",
		"messages": conversation_history, # Envia todo o histórico acumulado
		"temperature": 1.0,
		"max_completion_tokens": 1024
	}
	
	var body = JSON.stringify(payload)
	var error = http_request.request(API_URL, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		http_request.queue_free()
		return "Erro ao iniciar requisição HTTP."
		
	var result = await http_request.request_completed
	http_request.queue_free()
	
	var response_code = result[1]
	var body_data = result[3]
	var response_text = body_data.get_string_from_utf8()
	
	if response_code == 200:
		var json = JSON.parse_string(response_text)
		if json and json.has("choices"):
			var resposta_ia = json["choices"][0]["message"]["content"]
			# Adiciona a resposta da IA ao histórico para manter o contexto futuro
			conversation_history.append({"role": "assistant", "content": resposta_ia})
			return resposta_ia
			
	return "Erro " + str(response_code) + ": " + response_text

# Função opcional para limpar o histórico caso queira reiniciar a conversa
func clear_history() -> void:
	conversation_history.clear()
