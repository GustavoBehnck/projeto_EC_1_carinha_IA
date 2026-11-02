extends Control

@onready var input_estudante = $LineEdit
@onready var display_resposta = $RichTextLabel
@onready var botao = $Button

const GroqClientScript = preload("res://groq_client.gd")
var groq = GroqClientScript.new()

func _ready() -> void:
	add_child(groq)
	if botao:
		if not botao.pressed.is_connected(_on_button_pressed):
			botao.pressed.connect(_on_button_pressed)
	else:
		print("ERRO: O nó Button não foi encontrado com esse nome!")

func _on_button_pressed() -> void:
	print("Botão pressionado com sucesso!")
	var texto_usuario = input_estudante.text.strip_edges()
	if texto_usuario.is_empty():
		display_resposta.text = "Digite algo primeiro!"
		return

	display_resposta.text = "Pensando..."
	botao.disabled = true

	var resposta = await groq.ask_groq(texto_usuario)
	
	display_resposta.text = resposta
	botao.disabled = false
