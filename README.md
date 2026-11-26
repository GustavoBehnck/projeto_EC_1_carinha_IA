# Assistente Virtual Acadêmico (AVA)

## 👥 Integrantes
- Gustavo Behnck Cardoso
- Matheus Henrique Gonçalves Rodrigues

## 📌 Descrição
O **Assistente Virtual Acadêmico (AVA)** é uma aplicação móvel interativa projetada para atuar como um guia inteligente em tempo real em ambientes universitários. O sistema mitiga barreiras de usabilidade e localização causadas pela intensa dinâmica espacial e constantes realocações de salas e eventos no campus.

## 🛠️ Tecnologias
- **Frontend / Mobile:** Godot Engine (GDScript), Avatar 2D com expressões dinâmicas, Android Native Audio Services (Speech-to-Text e Text-to-Speech)
- **Backend / Inteligência Artificial:** Integração assíncrona via API HTTP/REST com Modelo de Linguagem de Grande Escala (LLM) em nuvem
- **Segurança:** Criptografia em trânsito (TLS 1.3) e em repouso (AES-256)

## ⚙️ Como executar
1. Clone o repositório
2. Abra o **Godot Engine** (utilizando a versão compatível com o projeto), clique em **Importar** e selecione o arquivo `project.godot`.
3. Configure sua chaves de API do groq no arquivo de configuração `groq_token.txt` ou `.groq_token`.
5. Exporte ou execute o projeto para **Android** no Godot (com Android Build Template / SDK configurados e permissões de microfone habilitadas) em um dispositivo físico ou emulador.

## 🔗 Repositório
https://github.com/GustavoBehnck/projeto_EC_1_AVA
