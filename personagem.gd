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

var botao_historico: Button
var painel_historico: Panel
var texto_historico: RichTextLabel
var lista_historico: Array[String] = []

var particulas_emocao: CPUParticles2D

var emocao_atual: String = "PADRAO"
var cor_atual: Color = Color("#FFFFFF")
var tempo_idle: float = 0.0
var timer_piscar: float = 0.0
var piscando_olhos: bool = false
var pos_y_base_rosto: float = 85.0
var offset_y_emocao: float = 0.0
var intensidade_tremor: float = 0.0
var tween_rosto: Tween

var estilo_botao_normal: StyleBoxFlat
var estilo_botao_gravando: StyleBoxFlat
var estilo_botao_topo: StyleBoxFlat
var estilo_input: StyleBoxFlat
var fundo_painel: ColorRect

var fila_emocoes_tts: Dictionary = {}
var proximo_id_fala: int = 1
var id_sessao_fala: int = 0

const EMOTES = {
	"PADRAO":      {"texto": "( •‿• )",     "cor": Color("#FFFFFF"), "pitch": 1.0,  "rate": 1.0,  "stability": 0.50, "style": 0.20},
	"OUVINDO":     {"texto": "( ⊙_⊙ )",     "cor": Color("#00E5FF"), "pitch": 1.0,  "rate": 1.0,  "stability": 0.50, "style": 0.20},
	"PENSANDO":    {"texto": "( -_ - )",    "cor": Color("#B388FF"), "pitch": 0.9,  "rate": 0.85, "stability": 0.65, "style": 0.15},
	"ERRO":        {"texto": "( >_< )",     "cor": Color("#FF5252"), "pitch": 0.85, "rate": 0.95, "stability": 0.40, "style": 0.45},
	"RAIVA":       {"texto": "( ╬`益´ )",   "cor": Color("#FF1744"), "pitch": 0.75, "rate": 1.25, "stability": 0.30, "style": 0.80},
	"FELIZ":       {"texto": "( ^_^ )",     "cor": Color("#FFD600"), "pitch": 1.15, "rate": 1.1,  "stability": 0.40, "style": 0.45},
	"MUITO_FELIZ": {"texto": "( ≧▽≦ )",     "cor": Color("#FFFF00"), "pitch": 1.3,  "rate": 1.25, "stability": 0.30, "style": 0.70},
	"RINDO":       {"texto": "( ^▽^ )",     "cor": Color("#FFC400"), "pitch": 1.25, "rate": 1.2,  "stability": 0.30, "style": 0.65},
	"EMPOLGADO":   {"texto": "\\( ★ω★ )/",  "cor": Color("#FFEA00"), "pitch": 1.35, "rate": 1.25, "stability": 0.30, "style": 0.75},
	"SURPRESO":    {"texto": "( 〇_〇 )",   "cor": Color("#18FFFF"), "pitch": 1.3,  "rate": 1.15, "stability": 0.35, "style": 0.60},
	"ORGULHOSO":   {"texto": "( ˘⌣˘ )",     "cor": Color("#69F0AE"), "pitch": 1.05, "rate": 1.0,  "stability": 0.50, "style": 0.40},
	"TIMIDO":      {"texto": "( •_•; )",    "cor": Color("#FF80AB"), "pitch": 1.1,  "rate": 0.95, "stability": 0.50, "style": 0.35},
	"PISCANDO":    {"texto": "( ^_~ )",     "cor": Color("#69F0AE"), "pitch": 1.1,  "rate": 1.05, "stability": 0.45, "style": 0.40},
	"BRINCALHAO":  {"texto": "( •̀ᴗ•́ )و",    "cor": Color("#FF9100"), "pitch": 1.2,  "rate": 1.15, "stability": 0.35, "style": 0.60},
	"PENSATIVO":   {"texto": "( ¬_¬ )",     "cor": Color("#CE93D8"), "pitch": 0.9,  "rate": 0.85, "stability": 0.65, "style": 0.15},
	"CONFUSO":     {"texto": "( ・_・? )",   "cor": Color("#FFB74D"), "pitch": 1.15, "rate": 0.9,  "stability": 0.40, "style": 0.40},
	"TRISTE":      {"texto": "( T_T )",     "cor": Color("#448AFF"), "pitch": 0.8,  "rate": 0.75, "stability": 0.60, "style": 0.50}
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
	
	configurar_particulas_emocao()
	
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
		
	botao_acessibilidade.add_theme_stylebox_override("normal", estilo_botao_topo)
	botao_acessibilidade.add_theme_stylebox_override("hover", estilo_botao_topo)
	botao_acessibilidade.add_theme_stylebox_override("pressed", estilo_botao_topo)
		
	if not botao_acessibilidade.pressed.is_connected(_on_botao_acessibilidade_pressed):
		botao_acessibilidade.pressed.connect(_on_botao_acessibilidade_pressed)
		
	configurar_interface_historico()
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
	
	estilo_botao_topo = StyleBoxFlat.new()
	estilo_botao_topo.bg_color = Color("#1E2433")
	estilo_botao_topo.set_corner_radius_all(14)
	
	estilo_input = StyleBoxFlat.new()
	estilo_input.bg_color = Color("#1E2433")
	estilo_input.set_corner_radius_all(16)
	estilo_input.content_margin_left = 18
	estilo_input.content_margin_right = 18
	if input_estudante:
		input_estudante.add_theme_stylebox_override("normal", estilo_input)
		input_estudante.add_theme_stylebox_override("focus", estilo_input)

func configurar_particulas_emocao() -> void:
	particulas_emocao = CPUParticles2D.new()
	particulas_emocao.emitting = false
	particulas_emocao.amount = 35
	particulas_emocao.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particulas_emocao.emission_rect_extents = Vector2(140, 40)
	add_child(particulas_emocao)

func configurar_interface_historico() -> void:
	botao_historico = Button.new()
	botao_historico.name = "BotaoHistorico"
	botao_historico.text = "📜 Histórico"
	botao_historico.size = Vector2(180, 55)
	botao_historico.position = Vector2(20, 20)
	botao_historico.add_theme_font_size_override("font_size", 20)
	botao_historico.add_theme_stylebox_override("normal", estilo_botao_topo)
	botao_historico.add_theme_stylebox_override("hover", estilo_botao_topo)
	botao_historico.add_theme_stylebox_override("pressed", estilo_botao_topo)
	botao_historico.pressed.connect(_on_botao_historico_pressed)
	add_child(botao_historico)
	
	painel_historico = Panel.new()
	painel_historico.visible = false
	var estilo_painel = StyleBoxFlat.new()
	estilo_painel.bg_color = Color(0.08, 0.1, 0.15, 0.97)
	estilo_painel.set_corner_radius_all(20)
	painel_historico.add_theme_stylebox_override("panel", estilo_painel)
	add_child(painel_historico)
	
	var titulo = Label.new()
	titulo.text = "Histórico de Interações"
	titulo.position = Vector2(25, 18)
	titulo.add_theme_font_size_override("font_size", 26)
	painel_historico.add_child(titulo)
	
	var btn_fechar = Button.new()
	btn_fechar.name = "BtnFechar"
	btn_fechar.text = "✖ Fechar"
	btn_fechar.size = Vector2(130, 48)
	btn_fechar.add_theme_font_size_override("font_size", 20)
	btn_fechar.add_theme_stylebox_override("normal", estilo_botao_gravando)
	btn_fechar.add_theme_stylebox_override("hover", estilo_botao_gravando)
	btn_fechar.pressed.connect(func(): painel_historico.visible = false)
	painel_historico.add_child(btn_fechar)
	
	texto_historico = RichTextLabel.new()
	texto_historico.name = "TextoHistorico"
	texto_historico.bbcode_enabled = true
	texto_historico.scroll_active = true
	texto_historico.scroll_following = true
	texto_historico.add_theme_font_size_override("normal_font_size", 24)
	texto_historico.add_theme_font_size_override("bold_font_size", 24)
	texto_historico.text = "Nenhuma interação registrada ainda."
	painel_historico.add_child(texto_historico)

func _on_botao_historico_pressed() -> void:
	painel_historico.visible = not painel_historico.visible
	if painel_historico.visible:
		painel_historico.move_to_front()

func registrar_no_historico(pergunta: String, resposta: String) -> void:
	var item = "[color=#00E5FF][b]Você:[/b][/color] " + pergunta + "\n[color=#FFD600][b]Assistente:[/b][/color] " + resposta
	lista_historico.append(item)
	if texto_historico:
		texto_historico.text = "\n\n────────────────────\n\n".join(lista_historico)

func _process(delta: float) -> void:
	var altura_teclado = DisplayServer.virtual_keyboard_get_height()
	var tamanho_tela = get_viewport_rect().size
	
	if altura_teclado != ultima_altura_teclado or tamanho_tela != ultimo_tamanho_tela:
		ultima_altura_teclado = altura_teclado
		ultimo_tamanho_tela = tamanho_tela
		atualizar_layout_acessibilidade()
		
	tempo_idle += delta
	if face_label:
		var tremor_x = randf_range(-intensidade_tremor, intensidade_tremor)
		var tremor_y = randf_range(-intensidade_tremor, intensidade_tremor)
		face_label.position.x = tremor_x
		face_label.position.y = pos_y_base_rosto + offset_y_emocao + sin(tempo_idle * 2.5) * 8.0 + tremor_y
		
		if particulas_emocao:
			particulas_emocao.position = face_label.position + (face_label.size / 2.0)
		
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
	intensidade_tremor = 0.0
	offset_y_emocao = 0.0
	
	if particulas_emocao:
		particulas_emocao.emitting = false
	if tween_rosto and tween_rosto.is_valid():
		tween_rosto.kill()
		
	var dados = EMOTES.get(emocao, EMOTES["PADRAO"])
	face_label.text = dados["texto"]
	var cor_alvo: Color = dados["cor"]
	
	face_label.pivot_offset = face_label.size / 2.0
	tween_rosto = create_tween().set_parallel(true)
	tween_rosto.tween_method(_aplicar_cor_rosto, cor_atual, cor_alvo, 0.25)
	cor_atual = cor_alvo
	
	match emocao:
		"FELIZ", "MUITO_FELIZ", "RINDO", "EMPOLGADO":
			var escala_max = Vector2(1.25, 1.25) if emocao != "FELIZ" else Vector2(1.14, 1.14)
			face_label.scale = Vector2(0.8, 0.8)
			tween_rosto.tween_property(face_label, "scale", escala_max, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tween_rosto.tween_property(face_label, "rotation_degrees", 0.0, 0.2)
			
			var tween_pulo = create_tween().set_loops(3)
			tween_pulo.tween_property(self, "offset_y_emocao", -28.0, 0.14).set_trans(Tween.TRANS_SINE)
			tween_pulo.tween_property(self, "offset_y_emocao", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
			
			if emocao != "FELIZ" and particulas_emocao:
				_ativar_particulas("ALEGRIA")
				
		"TRISTE":
			tween_rosto.tween_property(face_label, "scale", Vector2(0.72, 0.72), 0.5).set_trans(Tween.TRANS_SINE)
			tween_rosto.tween_property(face_label, "rotation_degrees", -6.0, 0.5)
			tween_rosto.tween_property(self, "offset_y_emocao", 32.0, 0.5)
			if particulas_emocao:
				_ativar_particulas("CHORO")
				
		"RAIVA":
			intensidade_tremor = 9.0
			face_label.scale = Vector2(0.9, 0.9)
			tween_rosto.tween_property(face_label, "scale", Vector2(1.22, 1.22), 0.2).set_trans(Tween.TRANS_BACK)
			tween_rosto.tween_property(face_label, "rotation_degrees", 0.0, 0.1)
			if particulas_emocao:
				_ativar_particulas("FOGO")
				
		"CONFUSO", "PENSATIVO", "TIMIDO":
			var angulo = 12.0 if emocao == "CONFUSO" else -8.0
			tween_rosto.tween_property(face_label, "scale", Vector2(0.95, 0.95), 0.25)
			tween_rosto.tween_property(face_label, "rotation_degrees", angulo, 0.3).set_trans(Tween.TRANS_BACK)
			
		"SURPRESO":
			face_label.scale = Vector2(0.5, 0.5)
			tween_rosto.tween_property(face_label, "scale", Vector2(1.28, 1.28), 0.22).set_trans(Tween.TRANS_ELASTIC)
			tween_rosto.tween_property(face_label, "rotation_degrees", 0.0, 0.15)
			
		_:
			face_label.scale = Vector2(0.88, 0.88)
			tween_rosto.tween_property(face_label, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK)
			tween_rosto.tween_property(face_label, "rotation_degrees", 0.0, 0.2)

func _ativar_particulas(tipo: String) -> void:
	if tipo == "FOGO":
		particulas_emocao.amount = 45
		particulas_emocao.lifetime = 0.85
		particulas_emocao.direction = Vector2(0, -1)
		particulas_emocao.spread = 35.0
		particulas_emocao.gravity = Vector2(0, -260)
		particulas_emocao.initial_velocity_min = 90.0
		particulas_emocao.initial_velocity_max = 200.0
		particulas_emocao.scale_amount_min = 12.0
		particulas_emocao.scale_amount_max = 26.0
		var grad = Gradient.new()
		grad.set_color(0, Color("#FF1744"))
		grad.add_point(0.5, Color("#FF9100"))
		grad.set_color(1, Color(1.0, 0.9, 0.0, 0.0))
		particulas_emocao.color_ramp = grad
	elif tipo == "CHORO":
		particulas_emocao.amount = 18
		particulas_emocao.lifetime = 1.0
		particulas_emocao.direction = Vector2(0, 1)
		particulas_emocao.spread = 20.0
		particulas_emocao.gravity = Vector2(0, 320)
		particulas_emocao.initial_velocity_min = 40.0
		particulas_emocao.initial_velocity_max = 90.0
		particulas_emocao.scale_amount_min = 7.0
		particulas_emocao.scale_amount_max = 12.0
		var grad = Gradient.new()
		grad.set_color(0, Color("#00E5FF"))
		grad.set_color(1, Color(0.2, 0.5, 1.0, 0.0))
		particulas_emocao.color_ramp = grad
	elif tipo == "ALEGRIA":
		particulas_emocao.amount = 30
		particulas_emocao.lifetime = 0.9
		particulas_emocao.direction = Vector2(0, -1)
		particulas_emocao.spread = 180.0
		particulas_emocao.gravity = Vector2(0, 60)
		particulas_emocao.initial_velocity_min = 100.0
		particulas_emocao.initial_velocity_max = 220.0
		particulas_emocao.scale_amount_min = 8.0
		particulas_emocao.scale_amount_max = 16.0
		var grad = Gradient.new()
		grad.set_color(0, Color("#FFFF00"))
		grad.set_color(1, Color(1.0, 0.8, 0.0, 0.0))
		particulas_emocao.color_ramp = grad
		
	particulas_emocao.emitting = true

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
	
	if botao_historico:
		botao_historico.size = Vector2(180, 55)
		botao_historico.position = Vector2(20.0, 20.0)
		botao_historico.move_to_front()
		
	if botao_acessibilidade:
		botao_acessibilidade.size = Vector2(210, 55)
		botao_acessibilidade.position = Vector2(largura_tela - 230.0, 20.0)
		botao_acessibilidade.move_to_front()
	
	if painel_historico:
		painel_historico.position = Vector2(25.0, 90.0)
		painel_historico.size = Vector2(largura_tela - 50.0, altura_tela - 130.0)
		var btn_fechar = painel_historico.get_node_or_null("BtnFechar")
		if btn_fechar:
			btn_fechar.position = Vector2(painel_historico.size.x - 150.0, 14.0)
		if texto_historico:
			texto_historico.position = Vector2(25.0, 75.0)
			texto_historico.size = Vector2(painel_historico.size.x - 50.0, painel_historico.size.y - 95.0)
		if painel_historico.visible:
			painel_historico.move_to_front()
	
	display_resposta.visible = modo_acessibilidade
	var tamanho_fonte = 80 if modo_acessibilidade else 110
	var limite_acima_input = input_estudante.position.y - 20.0
	pos_y_base_rosto = 85.0
	
	if modo_acessibilidade:
		botao_acessibilidade.text = "Ocultar Texto"
		var altura_rosto = maxf(140.0, (limite_acima_input - pos_y_base_rosto) * 0.32)
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
		
		botao.text = "⏹ PARAR E ENVIAR"
		botao.add_theme_stylebox_override("normal", estilo_botao_gravando)
		botao.add_theme_stylebox_override("hover", estilo_botao_gravando)
		display_resposta.text = "🎤 Ouvindo... Fale agora e toque no botão para enviar."
	else:
		gravando = false
		efeito_gravacao.set_recording_active(false)
		botao.scale = Vector2(1.0, 1.0)
		botao.text = "🎤 FALAR!"
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
		registrar_no_historico(pergunta, texto_limpo_tela)
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
