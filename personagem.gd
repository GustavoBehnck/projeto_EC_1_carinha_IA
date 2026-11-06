extends Control

@onready var input_estudante = $LineEdit
@onready var display_resposta = $RichTextLabel
@onready var botao = $Button
@onready var face_label: Label = get_node_or_null("FaceLabel")
@onready var botao_acessibilidade: Button = get_node_or_null("BotaoAcessibilidade")

const GroqClientScript = preload("res://groq_client.gd")
var groq = GroqClientScript.new()

var efeito_gravacao: AudioEffectRecord
var player_mic: AudioStreamPlayer
var player_eleven: AudioStreamPlayer
var bus_mic_idx: int = -1
var gravando: bool = false
var voz_id: String = ""

var modo_acessibilidade: bool = false
var ultima_altura_teclado: int = -1
var ultimo_tamanho_tela: Vector2 = Vector2.ZERO

# Controle de animações (Idle, Respiração e Piscar)
var emocao_atual: String = "PADRAO"
var cor_atual: Color = Color("#FFFFFF")
var tempo_idle: float = 0.0
var timer_piscar: float = 0.0
var piscando_olhos: bool = false
var pos_y_base_rosto: float = 80.0

# Estilos visuais dos botões
var estilo_botao_normal: StyleBoxFlat
var estilo_botao_gravando: StyleBoxFlat
var estilo_input: StyleBoxFlat
var fundo_painel: ColorRect

var fila_emocoes_tts: Dictionary = {}
var proximo_id_fala: int = 1
var id_sessao_fala: int = 0

# Dicionário com Kaomoji, Cor, Tom/Velocidade (TTS Nativo) e Stability/Style (ElevenLabs)
const EMOTES = {
	"PADRAO":      {"texto": "( •‿• )",   "cor": Color("#FFFFFF"), "pitch": 1.0,  "rate": 1.0,  "stability": 0.50, "style": 0.20},
	"OUVINDO":     {"texto": "( ⊙_⊙ )",   "cor": Color("#00E5FF"), "pitch": 1.0,  "rate": 1.0,  "stability": 0.50, "style": 0.20},
	"PENSANDO":    {"texto": "( -_ - )",  "cor": Color("#B388FF"), "pitch": 0.9,  "rate": 0.85, "stability": 0.65, "style": 0.15},
	"ERRO":        {"texto": "( >_< )",   "cor": Color("#FF5252"), "pitch": 0.85, "rate": 0.95, "stability": 0.40, "style": 0.45},
	"RAIVA":       {"texto": "( ╬ಠ益ಠ )", "cor": Color("#FF1744"), "pitch": 0.75, "rate": 1.25, "stability": 0.30, "style": 0.75},
	"FELIZ":       {"texto": "( ^_^ )",   "cor": Color("#FFD600"), "pitch": 1.15, "rate": 1.1,  "stability": 0.40, "style": 0.45},
	"MUITO_FELIZ": {"texto": "( ≧∇≦ )",   "cor": Color("#FFFF00"), "pitch": 1.3,  "rate": 1.25, "stability": 0.30, "style": 0.70},
	"RINDO":       {"texto": "( ⌒▽⌒ )",   "cor": Color("#FFC400"), "pitch": 1.25, "rate": 1.2,  "stability": 0.30, "style": 0.65},
	"PISCANDO":    {"texto": "( ^_~ )",   "cor": Color("#69F0AE"), "pitch": 1.1,  "rate": 1.05, "stability": 0.45, "style": 0.40},
	"BRINCALHAO":  {"texto": "( •̀ᴗ•́ )و",  "cor": Color("#FF9100"), "pitch": 1.2,  "rate": 1.15, "stability": 0.35, "style": 0.60},
	"PENSATIVO":   {"texto": "( ¬_¬ )",   "cor": Color("#CE93D8"), "pitch": 0.9,  "rate": 0.85, "stability": 0.65, "style": 0.15},
	"CONFUSO":     {"texto": "( ・_・? )", "cor": Color("#FFB74D"), "pitch": 1.15, "rate": 0.9,  "stability": 0.40, "style": 0.40},
	"TRISTE":      {"texto": "( T_T )",   "cor": Color("#448AFF"), "pitch": 0.8,  "rate": 0.75, "stability": 0.60, "style": 0.50}
}

func _ready() -> void:
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	OS.request_permissions()
	
	configurar_tema_visual()
	add_child(groq)
	
	player_eleven = AudioStreamPlayer.new()
	add_child(player_eleven)
	
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
		display_resposta.add_theme_font_size_override("normal_font_size", 28)
	
	if input_estudante:
		input_estudante.placeholder_text = "Digite sua dúvida aqui..."
		input_estudante.add_theme_font_size_override("font_size", 26)
		if not input_estudante.text_submitted.is_connected(_on_text_submitted):
			input_estudante.text_submitted.connect(_on_text_submitted)
	
	if botao_acessibilidade == null:
		botao_acessibilidade = Button.new()
		botao_acessibilidade.name = "BotaoAcessibilidade"
		add_child(botao_acessibilidade)
		botao_acessibilidade.add_theme_font_size_override("font_size", 20)
		botao_acessibilidade.size = Vector2(210, 55)
		
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
		botao.text = "🎤 FALAR!"
		botao.add_theme_font_size_override("font_size", 30)
		botao.add_theme_stylebox_override("normal", estilo_botao_normal)
		botao.add_theme_stylebox_override("hover", estilo_botao_normal)
		botao.add_theme_stylebox_override("pressed", estilo_botao_gravando)
		if not botao.pressed.is_connected(_on_button_pressed):
			botao.pressed.connect(_on_button_pressed)

func configurar_tema_visual() -> void:
	fundo_painel = ColorRect.new()
	fundo_painel.color = Color("#12161F")
	fundo_painel.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo_painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo_painel)
	move_child(fundo_painel, 0)
	
	estilo_botao_normal = StyleBoxFlat.new()
	estilo_botao_normal.bg_color = Color("#3D5AFE")
	estilo_botao_normal.set_corner_radius_all(25)
	estilo_botao_normal.shadow_color = Color(0, 0, 0, 0.35)
	estilo_botao_normal.shadow_size = 8
	
	estilo_botao_gravando = StyleBoxFlat.new()
	estilo_botao_gravando.bg_color = Color("#FF1744")
	estilo_botao_gravando.set_corner_radius_all(25)
	estilo_botao_gravando.shadow_color = Color(1, 0.1, 0.2, 0.4)
	estilo_botao_gravando.shadow_size = 12
	
	estilo_input = StyleBoxFlat.new()
	estilo_input.bg_color = Color("#1E2433")
	estilo_input.border_color = Color("#3D5AFE")
	estilo_input.set_border_width_all(2)
	estilo_input.set_corner_radius_all(16)
	estilo_input.content_margin_left = 18
	estilo_input.content_margin_right = 18
	if input_estudante:
		input_estudante.add_theme_stylebox_override("normal", estilo_input)
		input_estudante.add_theme_stylebox_override("focus", estilo_input)

func _process(delta: float) -> void:
	var altura_teclado = DisplayServer.virtual_keyboard_get_height()
	var tamanho_tela = get_viewport_rect().size
	
	if altura_teclado != ultima_altura_teclado or tamanho_tela != ultimo_tamanho_tela:
		ultima_altura_teclado = altura_teclado
		ultimo_tamanho_tela = tamanho_tela
		atualizar_layout_acessibilidade()
		
	tempo_idle += delta
	if face_label:
		face_label.position.y = pos_y_base_rosto + sin(tempo_idle * 2.5) * 8.0
		
	if emocao_atual == "PADRAO" and not gravando:
		timer_piscar += delta
		if not piscando_olhos and timer_piscar >= 3.8:
			piscando_olhos = true
			timer_piscar = 0.0
			face_label.text = "( -‿- )"
		elif piscando_olhos and timer_piscar >= 0.18:
			piscando_olhos = false
			timer_piscar = 0.0
			face_label.text = EMOTES["PADRAO"]["texto"]
			
	if gravando and bus_mic_idx != -1:
		var db = AudioServer.get_bus_peak_volume_left_db(bus_mic_idx, 0)
		var pulso = 1.0 + clampf((db + 60.0) / 300.0, 0.0, 0.12)
		botao.scale = Vector2(pulso, pulso)

func _on_text_submitted(_novo_texto: String) -> void:
	DisplayServer.virtual_keyboard_hide()
	_on_button_pressed()

func mudar_rosto(emocao: String) -> void:
	if not face_label:
		return
		
	emocao_atual = emocao
	piscando_olhos = false
	timer_piscar = 0.0
	
	var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
	face_label.rotation_degrees = 0.0
	face_label.text = dados["texto"]
	
	var cor_alvo: Color = dados["cor"]
	
	face_label.pivot_offset = face_label.size / 2.0
	face_label.scale = Vector2(0.82, 0.82)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(face_label, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(_aplicar_cor_rosto, cor_atual, cor_alvo, 0.25)
	cor_atual = cor_alvo

func _aplicar_cor_rosto(c: Color) -> void:
	if face_label.label_settings != null:
		face_label.label_settings.font_color = c
	else:
		face_label.add_theme_color_override("font_color", c)

func _on_botao_acessibilidade_pressed() -> void:
	modo_acessibilidade = not modo_acessibilidade
	atualizar_layout_acessibilidade()

func atualizar_layout_acessibilidade() -> void:
	var rect_tela = get_viewport_rect().size
	var largura_tela = rect_tela.x
	var altura_tela = rect_tela.y
	
	if fundo_painel:
		fundo_painel.size = rect_tela
	
	var altura_teclado_px = DisplayServer.virtual_keyboard_get_height()
	var escala_y = altura_tela / float(maxi(1, DisplayServer.window_get_size().y))
	var offset_teclado = altura_teclado_px * escala_y
	
	var base_util = altura_tela - offset_teclado - 30.0
	var margem_x = 40.0
	
	var altura_botao = 100.0
	var largura_botao = minf(380.0, largura_tela - (margem_x * 2.0))
	botao.size = Vector2(largura_botao, altura_botao)
	botao.pivot_offset = botao.size / 2.0
	botao.position = Vector2((largura_tela - largura_botao) / 2.0, base_util - altura_botao)
	
	var altura_input = 75.0
	input_estudante.size = Vector2(largura_tela - (margem_x * 2.0), altura_input)
	input_estudante.position = Vector2(margem_x, botao.position.y - altura_input - 20.0)
	
	botao_acessibilidade.position = Vector2(largura_tela - 230.0, 20.0)
	botao_acessibilidade.move_to_front()
	
	display_resposta.visible = modo_acessibilidade
	var tamanho_fonte = 80 if modo_acessibilidade else 115
	var limite_acima_input = input_estudante.position.y - 20.0
	pos_y_base_rosto = 80.0
	
	if modo_acessibilidade:
		botao_acessibilidade.text = "Ocultar Texto"
		var altura_rosto = maxf(140.0, (limite_acima_input - 80.0) * 0.32)
		face_label.position = Vector2(0, pos_y_base_rosto)
		face_label.size = Vector2(largura_tela, altura_rosto)
		
		var topo_texto = pos_y_base_rosto + face_label.size.y + 10.0
		display_resposta.position = Vector2(margem_x, topo_texto)
		display_resposta.size = Vector2(largura_tela - (margem_x * 2.0), maxf(80.0, limite_acima_input - topo_texto))
	else:
		botao_acessibilidade.text = "Mostrar Texto"
		face_label.position = Vector2(0, pos_y_base_rosto)
		face_label.size = Vector2(largura_tela, maxf(150.0, limite_acima_input - pos_y_base_rosto))
		
	face_label.pivot_offset = face_label.size / 2.0
	if face_label.label_settings != null:
		face_label.label_settings.font_size = tamanho_fonte
	else:
		face_label.add_theme_font_size_override("font_size", tamanho_fonte)

func _ao_iniciar_trecho_fala(utterance_id: int) -> void:
	if fila_emocoes_tts.has(utterance_id):
		mudar_rosto(fila_emocoes_tts[utterance_id])

func _ao_terminar_trecho_fala(utterance_id: int) -> void:
	fila_emocoes_tts.erase(utterance_id)
	if fila_emocoes_tts.is_empty():
		mudar_rosto("PADRAO")

func configurar_microfone() -> void:
	bus_mic_idx = AudioServer.get_bus_index("RecordBus")
	if bus_mic_idx == -1:
		bus_mic_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_mic_idx)
		AudioServer.set_bus_name(bus_mic_idx, "RecordBus")
		
		efeito_gravacao = AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus_mic_idx, efeito_gravacao)
	else:
		efeito_gravacao = AudioServer.get_bus_effect(bus_mic_idx, 0)
		
	AudioServer.set_bus_mute(bus_mic_idx, false)
	AudioServer.set_bus_volume_db(bus_mic_idx, -80.0)
		
	player_mic = AudioStreamPlayer.new()
	player_mic.stream = AudioStreamMicrophone.new()
	player_mic.bus = "RecordBus"
	add_child(player_mic)
	player_mic.play()

func interromper_fala_atual() -> void:
	id_sessao_fala += 1
	DisplayServer.tts_stop()
	fila_emocoes_tts.clear()
	if player_eleven and player_eleven.playing:
		player_eleven.stop()

func _on_button_pressed() -> void:
	DisplayServer.virtual_keyboard_hide()
	interromper_fala_atual()
	
	var texto_digitado = input_estudante.text.strip_edges()
	
	if not texto_digitado.is_empty() and not gravando:
		input_estudante.text = ""
		await processar_pergunta(texto_digitado)
		return
		
	if not gravando:
		if not player_mic.playing:
			player_mic.play()
			await get_tree().create_timer(0.2).timeout
		
		gravando = true
		efeito_gravacao.set_recording_active(true)
		mudar_rosto("OUVINDO")
		
		botao.text = "PARAR E ENVIAR"
		botao.add_theme_stylebox_override("normal", estilo_botao_gravando)
		botao.add_theme_stylebox_override("hover", estilo_botao_gravando)
		display_resposta.text = "Ouvindo... Fale agora e toque no botão para enviar."
	else:
		gravando = false
		efeito_gravacao.set_recording_active(false)
		botao.scale = Vector2(1.0, 1.0)
		botao.text = "FALAR!"
		botao.add_theme_stylebox_override("normal", estilo_botao_normal)
		botao.add_theme_stylebox_override("hover", estilo_botao_normal)
		
		mudar_rosto("PENSANDO")
		botao.disabled = true
		
		var gravacao = efeito_gravacao.get_recording()
		if gravacao == null or gravacao.data.size() < 2000:
			mudar_rosto("ERRO")
			display_resposta.text = "Áudio muito curto ou não captado."
			botao.disabled = false
			return
			
		if _audio_esta_mudo(gravacao.data):
			mudar_rosto("ERRO")
			display_resposta.text = "O microfone gravou apenas silêncio! Confirme 'Enable Input' em Project Settings > Audio > Driver."
			botao.disabled = false
			return
			
		display_resposta.text = "Transcrevendo sua voz..."
		
		var texto_falado = await groq.transcribe_audio(gravacao)
		if texto_falado.is_empty():
			mudar_rosto("CONFUSO")
			display_resposta.text = "Não consegui entender o que você falou."
			falar_simples("Não consegui entender o que você disse.", "CONFUSO")
			botao.disabled = false
			return
			
		await processar_pergunta(texto_falado)

func _audio_esta_mudo(dados: PackedByteArray) -> bool:
	var passo = maxi(2, dados.size() / 200)
	if passo % 2 != 0:
		passo += 1
	for i in range(0, dados.size() - 2, passo):
		if dados[i] != 0 or dados[i + 1] != 0:
			return false
	return true

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
	interromper_fala_atual()
	var sessao_atual = id_sessao_fala
	
	var regex = RegEx.new()
	regex.compile("\\[([A-Z_]+)\\]\\s*([^\\[]+)")
	var resultados = regex.search_all(resposta_bruta)
	
	if resultados.is_empty():
		falar_simples(resposta_bruta, "FELIZ")
		return
		
	if groq.tem_elevenlabs_configurado():
		for match_item in resultados:
			if sessao_atual != id_sessao_fala:
				return
			var emocao = match_item.get_string(1).strip_edges()
			var trecho_texto = match_item.get_string(2).strip_edges()
			if trecho_texto.is_empty():
				continue
				
			var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
			var stab: float = dados.get("stability", 0.45)
			var sty: float = dados.get("style", 0.35)
			
			mudar_rosto(emocao)
			var stream_mp3 = await groq.text_to_speech_elevenlabs(trecho_texto, stab, sty)
			if sessao_atual != id_sessao_fala:
				return
				
			if stream_mp3 != null:
				player_eleven.stream = stream_mp3
				player_eleven.play()
				await player_eleven.finished
			else:
				_falar_trecho_nativo(trecho_texto, emocao)
				return
				
		if sessao_atual == id_sessao_fala:
			mudar_rosto("PADRAO")
		return
		
	mudar_rosto(resultados[0].get_string(1).strip_edges())
	for match_item in resultados:
		var emocao = match_item.get_string(1).strip_edges()
		var trecho_texto = match_item.get_string(2).strip_edges()
		if not trecho_texto.is_empty():
			_falar_trecho_nativo(trecho_texto, emocao)

func _falar_trecho_nativo(trecho_texto: String, emocao: String) -> void:
	var id_atual = proximo_id_fala
	proximo_id_fala += 1
	fila_emocoes_tts[id_atual] = emocao
	
	var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
	var tom: float = dados.get("pitch", 1.0)
	var velocidade: float = dados.get("rate", 1.0)
	
	if voz_id != "":
		DisplayServer.tts_speak(trecho_texto, voz_id, 50, tom, velocidade, id_atual, false)

func falar_simples(texto: String, emocao: String = "FELIZ") -> void:
	interromper_fala_atual()
	var sessao_atual = id_sessao_fala
	mudar_rosto(emocao)
	
	if groq.tem_elevenlabs_configurado():
		var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
		var stream_mp3 = await groq.text_to_speech_elevenlabs(texto, dados.get("stability", 0.45), dados.get("style", 0.35))
		if sessao_atual != id_sessao_fala:
			return
		if stream_mp3 != null:
			player_eleven.stream = stream_mp3
			player_eleven.play()
			await player_eleven.finished
			if sessao_atual == id_sessao_fala:
				mudar_rosto("PADRAO")
			return
			
	_falar_trecho_nativo(texto, emocao)
