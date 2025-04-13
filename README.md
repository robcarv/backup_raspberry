# 🚀 Raspberry Pi Backup Automation

**Scripts para backup automatizado de múltiplos Raspberry Pi com Docker, incluindo verificação de pré-requisitos, compactação eficiente e notificações via Telegram.**

---

## 📌 Funcionalidades Principais

✅ **Backup completo** de múltiplos Raspberry Pi (suporte a RPi 4 e 5)  
✅ **Controle inteligente** de containers Docker (pausa/reinício automático)  
✅ **Verificação prévia** de requisitos com `checklist.sh`  
✅ **Upload seguro** para OneDrive via `rclone`  
✅ **Notificações** via Telegram com status detalhado  
✅ **Limpeza automática** de backups locais e remotos antigos  
✅ **Validação de integridade** dos backups  

---

## 🛠️ Pré-requisitos

- 📦 **Pacotes essenciais**:
  ```bash
  sudo apt install pv tar gzip curl docker.io

  🔑 Acesso SSH sem senha configurado nos Raspberry Pi

☁️ Rclone configurado com acesso ao OneDrive:
rclone config

⚙️ Configuração
Clone o repositório:

bash

git clone https://github.com/seu-usuario/raspberry-backup.git
cd raspberry-backup
Configure as variáveis (edite backup_rpi.sh ou use .env):

bash

# Exemplo .env (NUNCA faça commit deste arquivo!)
export RPI4_IP="192.168.x.x"
export RPI5_1_IP="192.168.x.x"
export RPI5_2_IP="192.168.x.x"
export BACKUP_BASE_DIR="/caminho/backups"
export ONEDRIVE_REMOTE="onedrive:/backups"
Dê permissões de execução:

chmod +x backup_rpi.sh checklist.sh

🚀 Como Usar
Execução completa (backup + upload + notificação):

./backup_rpi.sh



Fluxo do script:

Verifica pré-requisitos com checklist.sh

Para containers Docker nos dispositivos alvo

Cria backups compactados com:

/home/usuario/Documents

/var/lib/docker

/opt

Outros diretórios críticos

Reinicia os containers

Envia para OneDrive

Envia relatório para Telegram

Limpa backups locais (se sucesso)

📂 Estrutura de Arquivos

.
├── backup_rpi.sh          # Script principal
├── checklist.sh           # Verificador de pré-requisitos
├── .gitignore             # Ignora arquivos sensíveis
└── README.md              # Este arquivo


🔒 Boas Práticas de Segurança
NUNCA armazene credenciais diretamente nos scripts

Use sempre variáveis de ambiente para:

TELEGRAM_TOKEN
TELEGRAM_CHAT_ID

Revise periodicamente as permissões SSH

Mantenha logs em diretório seguro


📄 Licença
MIT License © 2025 - Robert Anderson Carvalho

