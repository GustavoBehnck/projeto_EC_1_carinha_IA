class_name GroqClient
extends Node

const API_URL = "https://api.groq.com/openai/v1/chat/completions"
var api_key: String = ""

func _init() -> void:
	load_token()

func load_token() -> void:
	var path = "res://.groq_token"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		api_key = file.get_as_text().strip_edges()
		file.close()
	else:
		print("ERRO: Arquivo .groq_token não encontrado na raiz do projeto!")

func ask_groq(prompt: String) -> String:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	var payload = {
		"model": "openai/gpt-oss-20b",
		"messages": [{"role": "user", "content": prompt}],
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
			return json["choices"][0]["message"]["content"]
			
	return "Erro " + str(response_code) + ": " + response_text
