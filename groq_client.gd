class_name GroqClient
extends Node

const CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
const AUDIO_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
const ELEVENLABS_URL = "https://api.elevenlabs.io/v1/text-to-speech/"

const FALLBACK_KEY = ""
const FALLBACK_ELEVEN_KEY = "" # Cole sua chave da ElevenLabs aqui (ou crie res://eleven_token.txt)

var api_key: String = ""
var elevenlabs_api_key: String = ""
var voice_id: String = "pFZP5JQG7iQjIQuC4Bku" # Voz padrão (Lily - Multilingual v2)
var conversation_history: Array = []

func _init() -> void:
	load_tokens()
	conversation_history.append({
		"role": "system",
		"content": "Você é o Assistente Virtual Acadêmico da Univap. Responda de forma clara, curta e natural. OBRIGATÓRIO: Sempre antes de cada frase ou mudança de tom, insira uma tag de humor entre colchetes: [FELIZ], [MUITO_FELIZ], [PISCANDO], [RINDO], [BRINCALHAO], [PENSATIVO], [CONFUSO], [TRISTE] ou [RAIVA]. Exemplo: [FELIZ] Olá! [PENSATIVO] Deixe-me ver o horário... [MUITO_FELIZ] Encontrei!"
	})

func load_tokens() -> void:
	# Carrega chave da Groq
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

	# Carrega chave da ElevenLabs
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

# 1. Transcrição de áudio via Groq Whisper (STT)
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

# 2. Envio de texto para o LLM da Groq
func ask_groq(prompt: String) -> String:
	if api_key.is_empty():
		return "Erro: Chave da API Groq não configurada."

	conversation_history.append({"role": "user", "content": "Responda usando tags de humor [FELIZ], [PENSATIVO], etc. antes de cada frase:\n" + prompt})

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

# 3. Síntese de Voz via ElevenLabs (Retorna AudioStreamMP3 pronto para tocar)
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
	else:
		print("Aviso ElevenLabs (HTTP ", result[1], ") - usando fallback nativo: ", result[3].get_string_from_utf8())
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
