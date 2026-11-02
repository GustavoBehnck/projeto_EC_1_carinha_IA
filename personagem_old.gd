extends Control

@onready var requisicao = $HTTPRequest
@onready var input_estudante = $LineEdit
@onready var display_resposta = $RichTextLabel
@onready var botao = $Button

var efeito_gravacao: AudioEffectRecord
var player_mic: AudioStreamPlayer
var player_retorno: AudioStreamPlayer
var gravando = false
var voz_id = ""

func _ready():
	# Pede a janela de permissão do Android na tela
	OS.request_permissions()
	
	# Configura a voz do sistema (TTS) em Português
	var vozes = DisplayServer.tts_get_voices_for_language("pt")
	if vozes.size() > 0:
		voz_id = vozes[0]
		
	configurar_microfone()
	botao.text = "FALAR!"
	display_resposta.text = "Toque em FALAR! para começar a gravar sua voz."

func configurar_microfone():
	# Cria um canal (Bus) de áudio exclusivo para o microfone e muta ele (para não dar microfonia)
	var bus_idx = AudioServer.bus_count
	AudioServer.add_bus(bus_idx)
	AudioServer.set_bus_name(bus_idx, "RecordBus")
	AudioServer.set_bus_mute(bus_idx, true)
	
	# Adiciona o efeito nativo de gravação da Godot nesse canal
	efeito_gravacao = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus_idx, efeito_gravacao)
	
	# Cria o captador do microfone físico do aparelho
	player_mic = AudioStreamPlayer.new()
	player_mic.stream = AudioStreamMicrophone.new()
	player_mic.bus = "RecordBus"
	add_child(player_mic)
	player_mic.play()
	
	# Cria um player para tocar o áudio gravado (teste)
	player_retorno = AudioStreamPlayer.new()
	add_child(player_retorno)

func _on_button_pressed():
	if not gravando:
		# INICIA A ESCUTA DO MICROFONE
		gravando = true
		efeito_gravacao.set_recording_active(true)
		botao.text = "PARAR DE FALAR"
		display_resposta.text = "🎤 Escutando... Fale no microfone e toque no botão para enviar!"
	else:
		# FINALIZA A ESCUTA
		gravando = false
		efeito_gravacao.set_recording_active(false)
		botao.text = "FALAR!"
		
		var gravacao = efeito_gravacao.get_recording()
		if gravacao != null:
			var bytes_audio = gravacao.get_data()
			display_resposta.text = "Áudio capturado com sucesso! (" + str(bytes_audio.size()) + " bytes).\nTocando sua gravação..."
			
			# Toca a sua voz de volta para provar que o microfone gravou:
			player_retorno.stream = gravacao
			player_retorno.play()
			
			# E fala com a voz do robô logo depois:
			falar("Eu escutei você perfeitamente, mas a inteligência artificial ainda não foi conectada.")
		else:
			display_resposta.text = "Nenhum som capturado no microfone."

func falar(texto: String):
	if voz_id != "":
		DisplayServer.tts_speak(texto, voz_id)
	else:
		var todas = DisplayServer.tts_get_voices()
		if todas.size() > 0:
			DisplayServer.tts_speak(texto, todas[0]["id"])
