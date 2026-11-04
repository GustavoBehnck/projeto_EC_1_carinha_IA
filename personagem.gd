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
var gravando: bool = false
var voz_id: String = ""

# Por padrão, começa com o texto oculto (apenas o avatar ocupando a tela)
var modo_acessibilidade: bool = false

var fila_emocoes_tts: Dictionary = {}
var proximo_id_fala: int = 1

# Dicionário com o Kaomoji e a cor associada a cada emoção
const EMOTES = {
	"PADRAO": {"texto": "( •‿• )", "cor": Color("#FFFFFF")},
	"OUVINDO": {"texto": "( ⊙_⊙ )", "cor": Color("#00E5FF")},
	"PENSANDO": {"texto": "( -_ - )", "cor": Color("#B388FF")},
	"ERRO": {"texto": "( >_< )", "cor": Color("#FF5252")},
	"RAIVA": {"texto": "( ╬ಠ益ಠ )", "cor": Color("#FF1744")},
	"FELIZ": {"texto": "( ^_^ )", "cor": Color("#FFD600")},
	"MUITO_FELIZ": {"texto": "( ≧∇≦ )", "cor": Color("#FFFF00")},
	"RINDO": {"texto": "( ⌒▽⌒ )", "cor": Color("#FFC400")},
	"PISCANDO": {"texto": "( ^_~ )", "cor": Color("#69F0AE")},
	"BRINCALHAO": {"texto": "( •̀ᴗ•́ )و", "cor": Color("#FF9100")},
	"PENSATIVO": {"texto": "( ¬_¬ )", "cor": Color("#CE93D8")},
	"CONFUSO": {"texto": "( ・_・? )", "cor": Color("#FFB74D")},
	"TRISTE": {"texto": "( T_T )", "cor": Color("#448AFF")}
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
	# Desativa a quebra de linha automática para o emote nunca partir ao meio
	face_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	
	# Cria o botão de Acessibilidade usando a largura real da tela (Viewport)
	if botao_acessibilidade == null:
		botao_acessibilidade = Button.new()
		botao_acessibilidade.name = "BotaoAcessibilidade"
		add_child(botao_acessibilidade)
		botao_acessibilidade.add_theme_font_size_override("font_size", 22)
		var largura_tela = get_viewport_rect().size.x
		botao_acessibilidade.size = Vector2(200, 55)
		botao_acessibilidade.position = Vector2(largura_tela - 220, 20)
		
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

func mudar_rosto(emocao: String) -> void:
	if not face_label:
		return
		
	var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
	face_label.rotation_degrees = 0.0
	face_label.text = dados["texto"]
	
	var cor_emocao: Color = dados["cor"]
	
	# Aplica a cor tanto no LabelSettings (se existir no Inspector) quanto no Theme Override
	if face_label.label_settings != null:
		face_label.label_settings.font_color = cor_emocao
	else:
		face_label.add_theme_color_override("font_color", cor_emocao)

func _on_botao_acessibilidade_pressed() -> void:
	modo_acessibilidade = not modo_acessibilidade
	atualizar_layout_acessibilidade()

func atualizar_layout_acessibilidade() -> void:
	display_resposta.visible = modo_acessibilidade
	var largura_tela = get_viewport_rect().size.x
	
	# Mantém o botão sempre no topo direito e na frente do Label
	botao_acessibilidade.position = Vector2(largura_tela - 220, 20)
	botao_acessibilidade.move_to_front()
	
	var tamanho_fonte = 80 if modo_acessibilidade else 115
	
	if modo_acessibilidade:
		botao_acessibilidade.text = "Ocultar Texto"
		face_label.position = Vector2(0, 70)
		face_label.size = Vector2(largura_tela, display_resposta.position.y - 70)
	else:
		botao_acessibilidade.text = "Mostrar texto"
		var limite_inferior = input_estudante.position.y - 20
		face_label.position = Vector2(0, 80)
		face_label.size = Vector2(largura_tela, limite_inferior - 80)
		
	# Altera o tamanho da fonte mesmo se tiver LabelSettings criado no Inspector
	if face_label.label_settings != null:
		face_label.label_settings.font_size = tamanho_fonte
	else:
		face_label.add_theme_font_size_override("font_size", tamanho_fonte)

func _ao_iniciar_trecho_fala(utterance_id: int) -> void:
	if fila_emocoes_tts.has(utterance_id):
		mudar_rosto(fila_emocoes_tts[utterance_id])

func _ao_terminar_trecho_fala(utterance_id: int) -> void:
	fila_emocoes_tts.erase(utterance_id)

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
		
		# Atualiza o texto mesmo oculto (se o usuário clicar em Acessibilidade no meio da fala, o texto já estará lá!)
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
		
		if voz_id != "":
			DisplayServer.tts_speak(trecho_texto, voz_id, 50, 1.0, 1.0, id_atual, false)

func falar_simples(texto: String, emocao: String = "FELIZ") -> void:
	mudar_rosto(emocao)
	if voz_id != "":
		DisplayServer.tts_speak(texto, voz_id)
