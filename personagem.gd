extends Control

@onready var input_estudante = $LineEdit
@onready var display_resposta = $RichTextLabel
@onready var botao = $Button
@onready var face_label: Label = get_node_or_null("FaceLabel")
@onready var botao_acessibilidade: Button = get_node_or_null("BotaoAcessibilidade")

const GroqClientScript = preload("res://groq_client.gd")
var groq = GroqClientScript.new()

var player_eleven: AudioStreamPlayer

var efeito_gravacao: AudioEffectRecord
var player_mic: AudioStreamPlayer
var gravando: bool = false
var voz_id: String = ""

var modo_acessibilidade: bool = false
var ultima_altura_teclado: int = -1
var ultimo_tamanho_tela: Vector2 = Vector2.ZERO

var fila_emocoes_tts: Dictionary = {}
var proximo_id_fala: int = 1

# Dicionário com Kaomoji, Cor, Tom (pitch) e Velocidade (rate)
const EMOTES = {
	"PADRAO":      {"texto": "( •‿• )",   "cor": Color("#FFFFFF"), "pitch": 1.0,  "rate": 1.0},
	"OUVINDO":     {"texto": "( ⊙_⊙ )",   "cor": Color("#00E5FF"), "pitch": 1.0,  "rate": 1.0},
	"PENSANDO":    {"texto": "( -_ - )",  "cor": Color("#B388FF"), "pitch": 0.9,  "rate": 0.85},
	"ERRO":        {"texto": "( >_< )",   "cor": Color("#FF5252"), "pitch": 0.85, "rate": 0.95},
	"RAIVA":       {"texto": "( ╬ಠ益ಠ )", "cor": Color("#FF1744"), "pitch": 0.75, "rate": 1.25},
	"FELIZ":       {"texto": "( ^_^ )",   "cor": Color("#FFD600"), "pitch": 1.15, "rate": 1.1},
	"MUITO_FELIZ": {"texto": "( ≧∇≦ )",   "cor": Color("#FFFF00"), "pitch": 1.3,  "rate": 1.25},
	"RINDO":       {"texto": "( ⌒▽⌒ )",   "cor": Color("#FFC400"), "pitch": 1.25, "rate": 1.2},
	"PISCANDO":    {"texto": "( ^_~ )",   "cor": Color("#69F0AE"), "pitch": 1.1,  "rate": 1.05},
	"BRINCALHAO":  {"texto": "( •̀ᴗ•́ )و",  "cor": Color("#FF9100"), "pitch": 1.2,  "rate": 1.15},
	"PENSATIVO":   {"texto": "( ¬_¬ )",   "cor": Color("#CE93D8"), "pitch": 0.9,  "rate": 0.85},
	"CONFUSO":     {"texto": "( ・_・? )", "cor": Color("#FFB74D"), "pitch": 1.15, "rate": 0.9},
	"TRISTE":      {"texto": "( T_T )",   "cor": Color("#448AFF"), "pitch": 0.8,  "rate": 0.75}
}

func _ready() -> void:
	add_child(groq)
	OS.request_permissions()
	
	if face_label == null:
		face_label = Label.new()
		face_label.name = "FaceLabel"
		add_child(face_label)
		
	face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	
	if display_resposta:
		display_resposta.fit_content = false
		display_resposta.clip_contents = true
		display_resposta.scroll_active = true
		display_resposta.scroll_following = true
	
	if input_estudante and not input_estudante.text_submitted.is_connected(_on_text_submitted):
		input_estudante.text_submitted.connect(_on_text_submitted)
	
	if botao_acessibilidade == null:
		botao_acessibilidade = Button.new()
		botao_acessibilidade.name = "BotaoAcessibilidade"
		add_child(botao_acessibilidade)
		botao_acessibilidade.add_theme_font_size_override("font_size", 22)
		botao_acessibilidade.size = Vector2(200, 55)
		
	if not botao_acessibilidade.pressed.is_connected(_on_botao_acessibilidade_pressed):
		botao_acessibilidade.pressed.connect(_on_botao_acessibilidade_pressed)
	
	atualizar_layout_acessibilidade()
	mudar_rosto("PADRAO")
	
	var vozes = DisplayServer.tts_get_voices_for_language("pt")
	if vozes.size() > 0:
		voz_id = vozes[0]
	else:
		var todas = DisplayServer.tts_get_voices()
		if todas.size() > 0:
			voz_id = todas[0]["id"]
			
	DisplayServer.tts_set_utterance_callback(
		DisplayServer.TTS_UTTERANCE_STARTED,
		_ao_iniciar_trecho_fala
	)
	DisplayServer.tts_set_utterance_callback(
		DisplayServer.TTS_UTTERANCE_ENDED,
		_ao_terminar_trecho_fala
	)
		
	configurar_microfone()
	
	if botao:
		botao.text = "FALAR!"
		if not botao.pressed.is_connected(_on_button_pressed):
			botao.pressed.connect(_on_button_pressed)
			
	player_eleven = AudioStreamPlayer.new()
	add_child(player_eleven)

func _process(_delta: float) -> void:
	var altura_teclado = DisplayServer.virtual_keyboard_get_height()
	var tamanho_tela = get_viewport_rect().size
	
	if altura_teclado != ultima_altura_teclado or tamanho_tela != ultimo_tamanho_tela:
		ultima_altura_teclado = altura_teclado
		ultimo_tamanho_tela = tamanho_tela
		atualizar_layout_acessibilidade()

func _on_text_submitted(_novo_texto: String) -> void:
	DisplayServer.virtual_keyboard_hide()
	_on_button_pressed()

# Melhores estéticas: Animação suave de escala e transição de cor (Tween)
func mudar_rosto(emocao: String) -> void:
	if not face_label:
		return
		
	var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
	face_label.rotation_degrees = 0.0
	face_label.text = dados["texto"]
	
	var cor_alvo: Color = dados["cor"]
	
	# Aplica a cor atual
	if face_label.label_settings != null:
		face_label.label_settings.font_color = cor_alvo
	else:
		face_label.add_theme_color_override("font_color", cor_alvo)
		
	# Efeito de "Pop" suave (escala crescendo levemente e voltando ao normal)
	var tween = create_tween().set_parallel(true)
	face_label.scale = Vector2(0.85, 0.85)
	tween.tween_property(face_label, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_botao_acessibilidade_pressed() -> void:
	modo_acessibilidade = not modo_acessibilidade
	atualizar_layout_acessibilidade()

func atualizar_layout_acessibilidade() -> void:
	var rect_tela = get_viewport_rect().size
	var largura_tela = rect_tela.x
	var altura_tela = rect_tela.y
	
	var altura_teclado_px = DisplayServer.virtual_keyboard_get_height()
	var escala_y = altura_tela / float(maxi(1, DisplayServer.window_get_size().y))
	var offset_teclado = altura_teclado_px * escala_y
	
	var base_util = altura_tela - offset_teclado - 30.0
	var margem_x = 40.0
	
	var altura_botao = 100.0
	var largura_botao = minf(380.0, largura_tela - (margem_x * 2.0))
	botao.size = Vector2(largura_botao, altura_botao)
	botao.position = Vector2((largura_tela - largura_botao) / 2.0, base_util - altura_botao)
	
	var altura_input = 75.0
	input_estudante.size = Vector2(largura_tela - (margem_x * 2.0), altura_input)
	input_estudante.position = Vector2(margem_x, botao.position.y - altura_input - 20.0)
	
	botao_acessibilidade.position = Vector2(largura_tela - 220.0, 20.0)
	botao_acessibilidade.move_to_front()
	
	display_resposta.visible = modo_acessibilidade
	var tamanho_fonte = 80 if modo_acessibilidade else 115
	var limite_acima_input = input_estudante.position.y - 20.0
	
	if modo_acessibilidade:
		botao_acessibilidade.text = "Ocultar Texto"
		var altura_rosto = maxf(140.0, (limite_acima_input - 80.0) * 0.32)
		face_label.position = Vector2(0, 80.0)
		face_label.size = Vector2(largura_tela, altura_rosto)
		
		var topo_texto = face_label.position.y + face_label.size.y + 10.0
		display_resposta.position = Vector2(margem_x, topo_texto)
		display_resposta.size = Vector2(largura_tela - (margem_x * 2.0), maxf(80.0, limite_acima_input - topo_texto))
	else:
		botao_acessibilidade.text = "Mostrar texto"
		face_label.position = Vector2(0, 80.0)
		face_label.size = Vector2(largura_tela, maxf(150.0, limite_acima_input - 80.0))
		
	if face_label.label_settings != null:
		face_label.label_settings.font_size = tamanho_fonte
	else:
		face_label.add_theme_font_size_override("font_size", tamanho_fonte)

func _ao_iniciar_trecho_fala(utterance_id: int) -> void:
	if fila_emocoes_tts.has(utterance_id):
		mudar_rosto(fila_emocoes_tts[utterance_id])

# Retorna automaticamente para o rosto PADRÃO quando o assistente termina de falar tudo
func _ao_terminar_trecho_fala(utterance_id: int) -> void:
	fila_emocoes_tts.erase(utterance_id)
	if fila_emocoes_tts.is_empty():
		mudar_rosto("PADRAO")

func configurar_microfone() -> void:
	var bus_idx = AudioServer.get_bus_index("RecordBus")
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, "RecordBus")
		AudioServer.set_bus_mute(bus_idx, true)
		
		efeito_gravacao = AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus_idx, efeito_gravacao)
	else:
		efeito_gravacao = AudioServer.get_bus_effect(bus_idx, 0)
		
	player_mic = AudioStreamPlayer.new()
	player_mic.stream = AudioStreamMicrophone.new()
	player_mic.bus = "RecordBus"
	add_child(player_mic)
	player_mic.play()

func _on_button_pressed() -> void:
	DisplayServer.virtual_keyboard_hide()
	DisplayServer.tts_stop()
	fila_emocoes_tts.clear()
	
	var texto_digitado = input_estudante.text.strip_edges()
	
	if not texto_digitado.is_empty() and not gravando:
		input_estudante.text = ""
		await processar_pergunta(texto_digitado)
		return
		
	if not gravando:
		if not player_mic.playing:
			player_mic.play()
		gravando = true
		efeito_gravacao.set_recording_active(true)
		mudar_rosto("OUVINDO")
		botao.text = "PARAR E ENVIAR"
		display_resposta.text = "Ouvindo... Fale agora e toque no botão para enviar."
	else:
		gravando = false
		efeito_gravacao.set_recording_active(false)
		mudar_rosto("PENSANDO")
		botao.text = "FALAR!"
		botao.disabled = true
		display_resposta.text = "Transcrevendo sua voz..."
		
		var gravacao = efeito_gravacao.get_recording()
		if gravacao == null or gravacao.data.size() < 1000:
			mudar_rosto("ERRO")
			display_resposta.text = "Nenhum áudio captado no microfone."
			botao.disabled = false
			return
			
		var texto_falado = await groq.transcribe_audio(gravacao)
		if texto_falado.is_empty():
			mudar_rosto("CONFUSO")
			display_resposta.text = "Não consegui entender o que você falou."
			falar_simples("Não consegui entender o que você disse.", "CONFUSO")
			botao.disabled = false
			return
			
		await processar_pergunta(texto_falado)

func processar_pergunta(pergunta: String) -> void:
	botao.disabled = true
	mudar_rosto("PENSANDO")
	display_resposta.text = "Você disse: \"" + pergunta + "\"\n\nPensando..."
	
	var resposta_bruta = await groq.ask_groq(pergunta)
	
	if resposta_bruta.begins_with("Erro"):
		mudar_rosto("ERRO")
		display_resposta.text = resposta_bruta
	else:
		var regex_limpeza = RegEx.new()
		regex_limpeza.compile("\\[[A-Z_]+\\]\\s*")
		var texto_limpo_tela = regex_limpeza.sub(resposta_bruta, "", true).strip_edges()
		
		display_resposta.text = "Você: " + pergunta + "\n\nAssistente: " + texto_limpo_tela
		falar_com_emocoes_dinamicas(resposta_bruta)
		
	botao.disabled = false

func falar_com_emocoes_dinamicas(resposta_bruta: String) -> void:
	DisplayServer.tts_stop()
	fila_emocoes_tts.clear()
	
	var regex = RegEx.new()
	regex.compile("\\[([A-Z_]+)\\]\\s*([^\\[]+)")
	var resultados = regex.search_all(resposta_bruta)
	
	if resultados.is_empty():
		falar_simples(resposta_bruta, "FELIZ")
		return
		
	mudar_rosto(resultados[0].get_string(1).strip_edges())
	
	for match_item in resultados:
		var emocao = match_item.get_string(1).strip_edges()
		var trecho_texto = match_item.get_string(2).strip_edges()
		
		if trecho_texto.is_empty():
			continue
			
		var id_atual = proximo_id_fala
		proximo_id_fala += 1
		
		fila_emocoes_tts[id_atual] = emocao
		
		var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
		var tom: float = dados.get("pitch", 1.0)
		var velocidade: float = dados.get("rate", 1.0)
		
		if voz_id != "":
			DisplayServer.tts_speak(trecho_texto, voz_id, 50, tom, velocidade, id_atual, false)

func falar_simples(texto: String, emocao: String = "FELIZ") -> void:
	mudar_rosto(emocao)
	
	# Pede o áudio gerado por IA à ElevenLabs
	var stream_audio = await groq.text_to_speech_elevenlabs(texto)
	if stream_audio != null:
		player_eleven.stream = stream_audio
		player_eleven.play()
		# Opcional: assim que o áudio terminar, volta o rosto para o padrão
		await player_eleven.finished
		mudar_rosto("PADRAO")
