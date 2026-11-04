class_name GroqClient
extends Node

const CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
const AUDIO_URL = "https://api.groq.com/openai/v1/audio/transcriptions"

# Se o arquivo não for exportado no APK do Android, cole sua chave aqui como fallback:
const FALLBACK_KEY = "" 

var api_key: String = ""
var conversation_history: Array = []

func _init() -> void:
	load_token()
	conversation_history.append({
		"role": "system",
		"content": "Você é o Assistente Virtual Acadêmico da Univap. Responda de forma clara e natural. OBRIGATÓRIO: Sempre antes de cada frase ou mudança de tom, insira uma tag de humor entre colchetes: [FELIZ], [MUITO_FELIZ], [PISCANDO], [RINDO], [BRINCALHAO], [PENSATIVO], [CONFUSO], [TRISTE] ou [RAIVA]. Exemplo: [FELIZ] Olá! [PENSATIVO] Deixe-me ver o horário... [MUITO_FELIZ] Encontrei!"
	})

func load_token() -> void:
	# Tenta ler groq_token.txt (recomendado para Android) ou .groq_token
	for path in ["res://groq_token.txt", "res://.groq_token"]:
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				api_key = file.get_as_text().strip_edges()
				file.close()
				if not api_key.is_empty():
					return
	api_key = FALLBACK_KEY

# 1. ENVIA O ÁUDIO DO MICROFONE PARA O GROQ WHISPER (STT)
func transcribe_audio(recording: AudioStreamWAV) -> String:
	if api_key.is_empty():
		return "ERRO: Chave da API Groq não encontrada no celular."
		
	var wav_bytes = _encode_wav_bytes(recording)
	var boundary = "----GodotGroqBoundary" + str(Time.get_ticks_msec())
	var body = PackedByteArray()
	
	# Monta o multipart/form-data exigido pela API de áudio da Groq
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
	add_child(http_request)
	var error = http_request.request_raw(AUDIO_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http_request.queue_free()
		return ""
		
	var result = await http_request.request_completed
	http_request.queue_free()
	
	var response_code = result[1]
	var response_text = result[3].get_string_from_utf8()
	
	if response_code == 200:
		var json = JSON.parse_string(response_text)
		if json and json.has("text"):
			return json["text"].strip_edges()
	else:
		print("Erro STT Groq (", response_code, "): ", response_text)
	return ""

# 2. ENVIA O TEXTO PARA O MODELO DE LINGUAGEM DO GROQ
func ask_groq(prompt: String) -> String:
	if api_key.is_empty():
		return "Erro: Chave da API (.groq_token) não foi carregada no APK! Adicione *.txt ou .groq_token na aba Resources do Export."

	conversation_history.append({
	"role": "user",
	"content": "Responda usando tags de humor [FELIZ], [PENSATIVO], [MUITO_FELIZ], etc. antes de cada frase:\n" + prompt
})

	var http_request = HTTPRequest.new()
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
	
	var response_code = result[1]
	var body_data = result[3]
	var response_text = body_data.get_string_from_utf8()
	
	if response_code == 200:
		var json = JSON.parse_string(response_text)
		if json and json.has("choices"):
			var resposta_ia = json["choices"][0]["message"]["content"]
			conversation_history.append({"role": "assistant", "content": resposta_ia})
			return resposta_ia
			
	return "Erro " + str(response_code) + ": " + response_text

func clear_history() -> void:
	conversation_history.clear()

# Gera o cabeçalho WAV em memória para não precisar salvar arquivo no armazenamento do Android
func _encode_wav_bytes(rec: AudioStreamWAV) -> PackedByteArray:
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
	header.put_16(1) # Formato PCM
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
