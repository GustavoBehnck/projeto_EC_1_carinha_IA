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

## 📚 Referências

BRASIL. Lei nº 13.709, de 14 de agosto de 2018. Lei Geral de Proteção de Dados Pessoais (LGPD). Diário Oficial da União: seção 1, Brasília, DF, ano 155, n. 157, p. 59-64, 15 ago. 2018. Disponível em: https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm. Acesso em: 21 nov. 2026.
BROWN, T. B. et al. Language Models are Few-Shot Learners. In: ADVANCES IN NEURAL INFORMATION PROCESSING SYSTEMS, 33., 2020. Red Hook: Curran Associates, 2020. p. 1877-1901. Disponível em: https://arxiv.org/abs/2005.14165. Acesso em: 21 nov. 2026.
JURAFSKY, D.; MARTIN, J. H. Speech and Language Processing: An Introduction to Natural Language Processing, Computational Linguistics, and Speech Recognition. 3. ed. Upper Saddle River: Prentice Hall, 2023. Disponível em: https://web.stanford.edu/~jurafsky/slp3/. Acesso em: 21 nov. 2026.
RESCORLA, E. The Transport Layer Security (TLS) Protocol Version 1.3. RFC 8446, IETF, ago. 2018. DOI: 10.17487/RFC8446. Disponível em: https://datatracker.ietf.org/doc/html/rfc8446. Acesso em: 21 nov. 2026.
VASWANI, A. et al. Attention Is All You Need. In: ADVANCES IN NEURAL INFORMATION PROCESSING SYSTEMS, 31., 2017, Long Beach. Anais... Red Hook: Curran Associates, 2017. p. 5998-6008. Disponível em: https://arxiv.org/abs/1706.03762. Acesso em: 21 nov. 2026.


## 🔗 Repositório
https://github.com/GustavoBehnck/projeto_EC_1_AVA
