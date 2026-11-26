class_name GroqClient
extends Node

const CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
const AUDIO_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
const ELEVENLABS_URL = "https://api.elevenlabs.io/v1/text-to-speech/"

const FALLBACK_KEY = ""
const FALLBACK_ELEVEN_KEY = ""

var api_key: String = ""
var elevenlabs_api_key: String = ""
var voice_id: String = "pFZP5JQG7iQjIQuC4Bku"
var conversation_history: Array = []

const SYSTEM_PROMPT = "Você é o Assistente Virtual Acadêmico da Univap. Responda de forma clara, curta e natural. OBRIGATÓRIO: Sempre antes de cada frase ou mudança de tom, insira uma tag de humor entre colchetes: [FELIZ], [MUITO_FELIZ], [PISCANDO], [RINDO], [BRINCALHAO], [PENSATIVO], [CONFUSO], [TRISTE], [RAIVA], [SURPRESO], [EMPOLGADO], [ORGULHOSO] ou [TIMIDO]. Exemplo: [FELIZ] Olá! [PENSATIVO] Deixe-me ver o horário... [EMPOLGADO] Encontrei!"

var _aulas_db: Array = [] # Cada item terá {"tags": Array[String], "info": String}

func _init() -> void:
	load_tokens()
	conversation_history.append({
		"role": "system",
		"content": SYSTEM_PROMPT
	})

const _MAPA_ACENTOS := {
	"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
	"é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i",
	"ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u",
	"ç": "c", "ñ": "n"
}

func _normalizar_texto(texto: String) -> String:
	var s := texto.to_lower()
	var out := ""
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		out += _MAPA_ACENTOS.get(ch, ch)
	return out

func _extrair_tokens(texto_norm: String) -> Array[String]:
	var stopwords := {
		"de": true, "da": true, "do": true, "das": true, "dos": true,
		"em": true, "no": true, "na": true, "nos": true, "nas": true,
		"o": true, "a": true, "os": true, "as": true, "um": true, "uma": true,
		"e": true, "ou": true, "para": true, "por": true, "com": true,
		"qual": true, "quais": true, "onde": true, "quando": true, "que": true
	}
	var partes := texto_norm.split(" ", false)
	var tokens: Array[String] = []
	for p in partes:
		var limpa := p.strip_edges()
		# Remove pontuação simples nas pontas
		limpa = limpa.trim_prefix("?").trim_prefix("¿").trim_prefix(",").trim_prefix(".")
		limpa = limpa.trim_suffix("?").trim_suffix("!").trim_suffix(",").trim_suffix(".")
		if limpa.length() >= 2 and not stopwords.has(limpa):
			tokens.append(limpa)
	return tokens

func carregar_aulas_json(caminho: String = "res://dados_univap.json") -> void:
	_aulas_db.clear()
	if not FileAccess.file_exists(caminho):
		push_warning("Arquivo de aulas não encontrado: " + caminho)
		return

	var file := FileAccess.open(caminho, FileAccess.READ)
	if not file:
		push_warning("Falha ao abrir arquivo de aulas: " + caminho)
		return

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_ARRAY:
		push_warning("JSON de aulas inválido: esperado um Array na raiz.")
		return

	for item in parsed:
		if typeof(item) != TYPE_DICTIONARY or not item.has("info"):
			continue

		var tags_normalizadas: Array[String] = []
		if item.has("tags") and typeof(item["tags"]) == TYPE_ARRAY:
			for t in item["tags"]:
				var limpa := _normalizar_texto(str(t))
				if not limpa.is_empty():
					tags_normalizadas.append(limpa)

		_aulas_db.append({
			"tags": tags_normalizadas,
			"info": str(item["info"]).strip_edges()
		})

func _montar_contexto_aulas(pergunta: String) -> String:
	var relevantes := buscar_aulas_relevantes(pergunta, 3)
	if relevantes.is_empty():
		return ""

	var linhas: Array[String] = []
	for info in relevantes:
		linhas.append("- " + info)

	return "\n\n[DADOS DAS AULAS RELEVANTES]\n" + "\n".join(linhas)

func buscar_aulas_relevantes(pergunta: String, limite: int = 3) -> Array[String]:
	var pergunta_norm := _normalizar_texto(pergunta)
	if pergunta_norm.is_empty() or _aulas_db.is_empty():
		return []

	var tokens := _extrair_tokens(pergunta_norm)
	var candidatos: Array = [] # {"score": int, "info": String}

	for registro in _aulas_db:
		var score := 0
		var tags: Array = registro["tags"]
		var info_norm := _normalizar_texto(registro["info"])

		for tag in tags:
			# 1. Tag completa aparece na pergunta (ex: "iot", "wagner clementino", "k520270")
			if pergunta_norm.contains(tag):
				score += 10 if tag.length() >= 4 else 6

			# 2. Comparação por palavras/tokens da pergunta
			for token in tokens:
				if tag == token:
					score += 5
				elif tag.contains(token) or token.contains(tag):
					# Evita falsos positivos em siglas curtas como "iot" ou "liu"
					if token.length() >= 4 and tag.length() >= 4:
						score += 3

		# 3. Fallback leve no texto de 'info' caso o termo não esteja nas tags
		for token in tokens:
			if token.length() >= 4 and info_norm.contains(token):
				score += 1

		if score > 0:
			candidatos.append({
				"score": score,
				"info": registro["info"]
			})

	candidatos.sort_custom(func(a, b): return a["score"] > b["score"])

	var resultado: Array[String] = []
	var qtd := mini(limite, candidatos.size())
	for i in range(qtd):
		resultado.append(candidatos[i]["info"])

	return resultado

func load_tokens() -> void:
	for path in ["res://groq_token.txt", "res://.groq_token"]:
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				api_key = file.get_as_text().strip_edges()
				file.close()
				if not api_key.is_empty():
					break
	if api_key.is_empty():
		api_key = FALLBACK_KEY

	for path in ["res://eleven_token.txt", "res://.eleven_token"]:
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				elevenlabs_api_key = file.get_as_text().strip_edges()
				file.close()
				if not elevenlabs_api_key.is_empty():
					break
	if elevenlabs_api_key.is_empty():
		elevenlabs_api_key = FALLBACK_ELEVEN_KEY

func tem_elevenlabs_configurado() -> bool:
	return not elevenlabs_api_key.is_empty() and elevenlabs_api_key != "SUA_CHAVE_ELEVENLABS_AQUI"

func transcribe_audio(recording: AudioStreamWAV) -> String:
	if api_key.is_empty():
		return ""
		
	var wav_bytes = _encode_wav_bytes(recording)
	var boundary = "----GodotGroqBoundary" + str(Time.get_ticks_msec())
	var body = PackedByteArray()
	
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"model\"\r\n\r\n".to_utf8_buffer())
	body.append_array("whisper-large-v3-turbo\r\n".to_utf8_buffer())
	
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"language\"\r\n\r\n".to_utf8_buffer())
	body.append_array("pt\r\n".to_utf8_buffer())
	
	var termos_guia = "Univap, FEAU, Bloco 10, Bloco 6, Auditório Jair, Lahoz, Carlos Lahoz, Pillat, Valdir Pillat, Raniero, Leandro Raniero, Liu Yao Cho, Lizia, Dors, Oli Dors, Muella, Penedo, Alexandre Penedo, Denilson, Simioni, Andreza Simioni, Erika Peterson, Wippich, Julia Wippich, Heidi, Yokoyama, Nara Yokoyama, Esperidião, Helio Esperidião, Scalambrino, Tardelli, Alexandre Tardelli, Arian Ojeda, Wallyson, Caio Mascarenhas, Lorenzini, Luca Lorenzini, Andre Olimpio, Beltrame, Milton Beltrame, Ivone Regina, Gabriel Doria, Papp, Marco Papp."
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".to_utf8_buffer())
	body.append_array((termos_guia + "\r\n").to_utf8_buffer())
	
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"file\"; filename=\"fala.wav\"\r\n".to_utf8_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
	body.append_array(wav_bytes)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())
	
	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: multipart/form-data; boundary=" + boundary
	]
	
	var http_request = HTTPRequest.new()
	http_request.timeout = 15.0
	add_child(http_request)
	
	var error = http_request.request_raw(AUDIO_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http_request.queue_free()
		return ""
		
	var result = await http_request.request_completed
	http_request.queue_free()
	
	if result[1] == 200:
		var json = JSON.parse_string(result[3].get_string_from_utf8())
		if json and json.has("text"):
			return json["text"].strip_edges()
	return ""

func _reset_system_prompt() -> void:
	conversation_history.clear()
	conversation_history.append({
		"role": "system",
		"content": SYSTEM_PROMPT
	})

func ask_groq(prompt: String) -> String:
	if api_key.is_empty():
		return "Erro: Chave da API Groq não configurada."

	# Garante que o prompt de sistema exista mesmo se o histórico foi alterado externamente
	if conversation_history.is_empty() or conversation_history[0].get("role", "") != "system":
		_reset_system_prompt()

	var contexto_aulas := _montar_contexto_aulas(prompt)
	var mensagem_usuario := "Responda usando tags de humor [FELIZ], [PENSATIVO], etc. antes de cada frase:\n" + prompt
	if not contexto_aulas.is_empty():
		mensagem_usuario += contexto_aulas

	conversation_history.append({
		"role": "user",
		"content": mensagem_usuario
	})

	var http_request = HTTPRequest.new()
	http_request.timeout = 15.0
	add_child(http_request)

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]

	var payload = {
		"model": "openai/gpt-oss-20b",
		"messages": conversation_history,
		"temperature": 1.0,
		"max_completion_tokens": 1024
	}

	var body = JSON.stringify(payload)
	var error = http_request.request(CHAT_URL, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		http_request.queue_free()
		return "Erro ao iniciar requisição HTTP."

	var result = await http_request.request_completed
	http_request.queue_free()

	if result[1] == 200:
		var json = JSON.parse_string(result[3].get_string_from_utf8())
		if json and json.has("choices"):
			var resposta_ia = json["choices"][0]["message"]["content"]
			conversation_history.append({"role": "assistant", "content": resposta_ia})
			return resposta_ia

	return "Erro " + str(result[1]) + ": " + result[3].get_string_from_utf8()

func text_to_speech_elevenlabs(text: String, stability: float = 0.45, style: float = 0.35) -> AudioStreamMP3:
	if not tem_elevenlabs_configurado():
		return null
		
	var url = ELEVENLABS_URL + voice_id + "?output_format=mp3_44100_128"
	
	var headers = [
		"Accept: audio/mpeg",
		"Content-Type: application/json",
		"xi-api-key: " + elevenlabs_api_key
	]
	
	var payload = {
		"text": text,
		"model_id": "eleven_multilingual_v2",
		"voice_settings": {
			"stability": stability,
			"similarity_boost": 0.75,
			"style": style,
			"use_speaker_boost": true
		}
	}
	
	var http_request = HTTPRequest.new()
	http_request.timeout = 15.0
	add_child(http_request)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		http_request.queue_free()
		return null
		
	var result = await http_request.request_completed
	http_request.queue_free()
	
	if result[1] == 200:
		var audio_stream = AudioStreamMP3.new()
		audio_stream.data = result[3]
		return audio_stream
	return null

func clear_history() -> void:
	conversation_history.clear()

func _encode_wav_bytes(rec: AudioStreamWAV) -> PackedByteArray:
	var temp_path = "user://temp_fala.wav"
	var err = rec.save_to_wav(temp_path)
	if err == OK and FileAccess.file_exists(temp_path):
		var file = FileAccess.open(temp_path, FileAccess.READ)
		if file:
			var wav_bytes = file.get_buffer(file.get_length())
			file.close()
			return wav_bytes
			
	var pcm = rec.data
	var channels = 2 if rec.stereo else 1
	var sample_rate = rec.mix_rate
	var bits_per_sample = 16
	var byte_rate = sample_rate * channels * (bits_per_sample / 8)
	var block_align = channels * (bits_per_sample / 8)
	
	var header = StreamPeerBuffer.new()
	header.big_endian = false
	header.put_data("RIFF".to_ascii_buffer())
	header.put_32(36 + pcm.size())
	header.put_data("WAVE".to_ascii_buffer())
	header.put_data("fmt ".to_ascii_buffer())
	header.put_32(16)
	header.put_16(1)
	header.put_16(channels)
	header.put_32(sample_rate)
	header.put_32(byte_rate)
	header.put_16(block_align)
	header.put_16(bits_per_sample)
	header.put_data("data".to_ascii_buffer())
	header.put_32(pcm.size())
	
	var wav = header.data_array
	wav.append_array(pcm)
	return wav
