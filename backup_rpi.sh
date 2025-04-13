#!/bin/bash

# Configurações
USER="youruser"
RPI4_IP="192.168.0.138"
RPI5_1_IP="192.168.0.139"
RPI5_2_IP="192.168.0.122"
BACKUP_BASE_DIR="/home/robert/backups"
LOG_FILE="/home/robert/Documents/logs/backup_log.txt"
ONEDRIVE_REMOTE="onedrive:/backups"

# Telegram Configurations
TELEGRAM_TOKEN="youtelegramtoken"  
TELEGRAM_CHAT_ID="idtelegram"                                   

# Cores para formatação
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# Arrays para rastrear backups bem-sucedidos e falhos
declare -a SUCCESSFUL_BACKUPS
declare -a FAILED_BACKUPS
declare -A BACKUP_SIZES
declare -a CURRENT_BACKUPS

# Função para obter timestamp formatado
get_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

# Função para imprimir mensagens formatadas
log_message() {
    local LEVEL=$1
    local MESSAGE=$2
    case $LEVEL in
        "INFO") COLOR=$BLUE ;;
        "SUCCESS") COLOR=$GREEN ;;
        "WARNING") COLOR=$YELLOW ;;
        "ERROR") COLOR=$RED ;;
        *) COLOR=$RESET ;;
    esac
    echo -e "${BOLD}$(get_timestamp)${RESET} ${COLOR}[${LEVEL}]${RESET} ${MESSAGE}" | tee -a "$LOG_FILE"
}

# Função para calcular o tamanho total do backup
calculate_total_backup_size() {
    local TOTAL_BACKUP_SIZE=0
    for SIZE in "${BACKUP_SIZES[@]}"; do
        if [ -n "$SIZE" ]; then
            TOTAL_BACKUP_SIZE=$(echo "$TOTAL_BACKUP_SIZE + $(numfmt --from=iec "$SIZE")" | bc)
        fi
    done
    echo "$(numfmt --to=iec "$TOTAL_BACKUP_SIZE")"
}

# Função para enviar mensagens ao Telegram
send_telegram() {
    local STATUS=$1
    local LOG_FILE=$2

    # Cria um arquivo temporário com extensão .txt
    local TEMP_FILE=$(mktemp).txt

    # Captura o output do checklist
    local CHECKLIST_OUTPUT=$(./checklist.sh)

    # Monta a mensagem com emojis e informações
    {
        echo "📅 Data: $(date)"
        echo "🔧 Hostname: "
        echo "✅ Backups bem-sucedidos:"
        
        # Adiciona os backups bem-sucedidos
        for HOSTNAME in "${SUCCESSFUL_BACKUPS[@]}"; do
            echo "   - $HOSTNAME"
        done

        # Adiciona a informação sobre backups com erro
        if [ ${#FAILED_BACKUPS[@]} -eq 0 ]; then
            echo "🎉 Nenhum backup com erro."
        else
            echo "❌ Backups com erro:"
            for HOSTNAME in "${FAILED_BACKUPS[@]}"; do
                echo "   - $HOSTNAME"
            done
        fi

        # Adiciona o tamanho total do backup
        echo "💾 Tamanho total do backup: $(calculate_total_backup_size)"

        # Adiciona o status e o caminho do log
        echo "📝 Status: $STATUS"
        echo "🔍 Ver logs: $LOG_FILE"

        # Adiciona o output do checklist
        echo -e "\n=== Checklist Output ==="
        echo "$CHECKLIST_OUTPUT"
    } > "$TEMP_FILE"

    # Envia o arquivo temporário como mensagem para o Telegram
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
        -F "chat_id=$TELEGRAM_CHAT_ID" \
        -F "document=@$TEMP_FILE" \
        -F "caption=Status do backup realizado em $(date)"

    # Verifica se o arquivo temporário foi enviado com sucesso
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "${GREEN}Arquivo de status enviado com sucesso.${RESET}"
    else
        log_message "ERROR" "${RED}Falha ao enviar o arquivo de status.${RESET}"
    fi

    # Deleta o arquivo temporário após o envio
    rm -f "$TEMP_FILE"

    # Envia o arquivo de log original como anexo
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
        -F "chat_id=$TELEGRAM_CHAT_ID" \
        -F "document=@$LOG_FILE" \
        -F "caption=Logs do backup realizado em $(date)"

    # Verifica se o arquivo de log foi enviado com sucesso
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "${GREEN}Arquivo de log enviado com sucesso.${RESET}"
        
        # Deleta o arquivo de log após o envio
        rm -f "$LOG_FILE"
        log_message "INFO" "${BLUE}Arquivo de log deletado: $LOG_FILE${RESET}"
    else
        log_message "ERROR" "${RED}Falha ao enviar o arquivo de log.${RESET}"
    fi
}

# Função para deletar backups antigos (mais de 15 dias)
delete_old_backups() {
    log_message "INFO" "${BOLD}${BLUE}=== Deleting backups older than 15 days in OneDrive remote ($ONEDRIVE_REMOTE) ===${RESET}"

    # Listar todas as pastas dentro do diretório de backup no OneDrive
    folders=$(rclone lsf --dirs-only "$ONEDRIVE_REMOTE" 2>>"$LOG_FILE")
    
    # Verificar se a listagem de pastas foi bem-sucedida
    if [ $? -ne 0 ]; then
        log_message "ERROR" "${RED}Failed to list folders from OneDrive remote ($ONEDRIVE_REMOTE).${RESET}"
        return 1
    fi

    # Verificar se há pastas para processar
    if [ -z "$folders" ]; then
        log_message "INFO" "${YELLOW}No folders found in OneDrive remote ($ONEDRIVE_REMOTE).${RESET}"
        return 0
    fi

    # Processar cada pasta
    while IFS= read -r folder; do
        log_message "INFO" "${BOLD}${BLUE}Processing folder: ${GREEN}$folder${RESET}"

        # Listar arquivos (não pastas) com mais de 15 dias dentro da pasta
        old_files=$(rclone lsf --files-only --format "p" --min-age 15d "$ONEDRIVE_REMOTE/$folder" 2>>"$LOG_FILE")
        
        if [ $? -ne 0 ]; then
            log_message "ERROR" "${RED}Failed to list files in folder $folder.${RESET}"
            continue
        fi

        # Verificar se há arquivos antigos na pasta
        if [ -z "$old_files" ]; then
            log_message "INFO" "${YELLOW}No files older than 15 days found in folder $folder.${RESET}"
            continue
        fi

        # Processar cada arquivo antigo
        while IFS= read -r file; do
            log_message "INFO" "${BOLD}Deleting ${BLUE}$file${RESET} from OneDrive..."
            rclone delete "$ONEDRIVE_REMOTE/$folder/$file" --log-file="$LOG_FILE"
            
            if [ $? -ne 0 ]; then
                log_message "ERROR" "${RED}Failed to delete $file.${RESET}"
            else
                log_message "SUCCESS" "${GREEN}$file deleted successfully.${RESET}"
            fi
        done <<< "$old_files"
    done <<< "$folders"

    log_message "INFO" "${BOLD}${BLUE}=== Old backups cleanup process completed ===${RESET}"
}

# Função para parar contêineres
stop_containers() {
    local IP=$1
    log_message "INFO" "${BOLD}Stopping containers on ${BLUE}$IP${RESET}..."

    # Listar todos os contêineres (em execução e parados)
    CONTAINERS=$(ssh $USER@$IP "docker ps -a --format '{{.Names}}'")
    if [ -z "$CONTAINERS" ]; then
        log_message "WARNING" "${YELLOW}No containers found on ${BLUE}$IP${RESET}."
    else
        log_message "INFO" "${BOLD}Containers on ${BLUE}$IP${RESET}:"
        for CONTAINER in $CONTAINERS; do
            STATUS=$(ssh $USER@$IP "docker inspect -f '{{.State.Status}}' $CONTAINER")
            log_message "INFO" " - ${BOLD}$CONTAINER${RESET} (Status: ${BOLD}$STATUS${RESET})"
        done

        # Parar apenas contêineres em execução
        RUNNING_CONTAINERS=$(ssh $USER@$IP "docker ps --format '{{.Names}}'")
        if [ -z "$RUNNING_CONTAINERS" ]; then
            log_message "WARNING" "${YELLOW}No running containers on ${BLUE}$IP${RESET}."
        else
            for CONTAINER in $RUNNING_CONTAINERS; do
                log_message "INFO" "${BOLD}Stopping container ${BLUE}$CONTAINER${RESET}..."
                ssh $USER@$IP "docker stop $CONTAINER"
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "${GREEN}Container ${BLUE}$CONTAINER${RESET} stopped successfully.${RESET}"
                else
                    log_message "ERROR" "${RED}Error stopping container ${BLUE}$CONTAINER${RESET}.${RESET}"
                    return 1
                fi
            done
        fi
    fi
}

# Função para iniciar contêineres
start_containers() {
    local IP=$1
    log_message "INFO" "${BOLD}Starting containers on ${BLUE}$IP${RESET}..."

    # Listar todos os contêineres (parados e em execução)
    CONTAINERS=$(ssh $USER@$IP "docker ps -a --format '{{.Names}}'")
    if [ -z "$CONTAINERS" ]; then
        log_message "WARNING" "${YELLOW}No containers found on ${BLUE}$IP${RESET}."
    else
        log_message "INFO" "${BOLD}Containers on ${BLUE}$IP${RESET}:"
        for CONTAINER in $CONTAINERS; do
            STATUS=$(ssh $USER@$IP "docker inspect -f '{{.State.Status}}' $CONTAINER")
            log_message "INFO" " - ${BOLD}$CONTAINER${RESET} (Status: ${BOLD}$STATUS${RESET})"
        done

        # Iniciar apenas contêineres parados
        STOPPED_CONTAINERS=$(ssh $USER@$IP "docker ps -a --filter 'status=exited' --format '{{.Names}}'")
        if [ -z "$STOPPED_CONTAINERS" ]; then
            log_message "WARNING" "${YELLOW}No stopped containers on ${BLUE}$IP${RESET}."
        else
            for CONTAINER in $STOPPED_CONTAINERS; do
                log_message "INFO" "${BOLD}Starting container ${BLUE}$CONTAINER${RESET}..."
                ssh $USER@$IP "docker start $CONTAINER"
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "${GREEN}Container ${BLUE}$CONTAINER${RESET} started successfully.${RESET}"
                else
                    log_message "ERROR" "${RED}Error starting container ${BLUE}$CONTAINER${RESET}.${RESET}"
                    return 1
                fi
            done
        fi
    fi
}

# Função para criar backup
backup() {
    local IP=$1
    local HOSTNAME=$(ssh $USER@$IP "hostname")
    local BACKUP_DIR="$BACKUP_BASE_DIR/$HOSTNAME"

    if [ -z "$HOSTNAME" ]; then
        log_message "ERROR" "${RED}Could not get hostname for ${BLUE}$IP${RESET}."
        FAILED_BACKUPS+=("Unknown")
        return 1
    fi

    # Criar diretório de backup se não existir
    mkdir -p "$BACKUP_DIR"

    local BACKUP_FILE="$BACKUP_DIR/${HOSTNAME}_$(date +%Y%m%d_%H%M%S).tar.gz"

    log_message "INFO" "${BOLD}Creating backup for ${BLUE}$HOSTNAME${RESET} (${BLUE}$IP${RESET})..."
    log_message "INFO" "${BOLD}Backup directory: ${BLUE}/home/robert/Documents${RESET}"

    # Obter o tamanho total dos arquivos a serem copiados (em bytes)
    local TOTAL_SIZE=$(ssh $USER@$IP "sudo du -sb /home/robert/Documents /home/robert/Downloads /var/lib/docker /opt/ /home/robert/Pictures /home/robert/Videos 2>/dev/null | awk '{total += \$1} END {printf \"%.0f\", total * 1.1}'")

    if [ -z "$TOTAL_SIZE" ] || [ "$TOTAL_SIZE" -eq 0 ]; then
        log_message "ERROR" "${RED}Failed to calculate total size of files to be backed up.${RESET}"
        FAILED_BACKUPS+=("$HOSTNAME")
        return 1
    fi

    log_message "INFO" "${BOLD}Total size to backup: ${BLUE}$(numfmt --to=iec --from=iec <<< "$TOTAL_SIZE")${RESET}"

    # Criar o arquivo .tar.gz com progresso usando pv
    log_message "INFO" "${BOLD}Creating and compressing backup...${RESET}"
    ssh $USER@$IP "sudo tar -cf - \
        /home/robert/Documents \
        /home/robert/Downloads \
        /opt \
        /var/lib/docker \
        /home/robert/Pictures \
        /home/robert/Videos 2>/dev/null" \
        | pv -s "$TOTAL_SIZE" \
        | gzip > "$BACKUP_FILE"

    if [ $? -eq 0 ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log_message "SUCCESS" "${GREEN}Backup for ${BLUE}$HOSTNAME${RESET} completed successfully. Size: ${BLUE}$BACKUP_SIZE${RESET}"
        SUCCESSFUL_BACKUPS+=("$HOSTNAME")
        BACKUP_SIZES["$HOSTNAME"]="$BACKUP_SIZE"  # Armazenar tamanho do backup
        CURRENT_BACKUPS+=("$BACKUP_FILE")  # Adicionar arquivo de backup ao array
    else
        log_message "ERROR" "${RED}Error creating backup for ${BLUE}$HOSTNAME${RESET}.${RESET}"
        FAILED_BACKUPS+=("$HOSTNAME")
    fi
}

# Função para enviar backups para o OneDrive
upload_to_onedrive() {
    log_message "INFO" "${BOLD}Uploading backups to OneDrive...${RESET}"
    rclone copy $BACKUP_BASE_DIR $ONEDRIVE_REMOTE --log-file=$LOG_FILE -v --progress
}

# Função para testar backups
test_backup() {
    local IP=$1
    local HOSTNAME=$(ssh $USER@$IP "hostname")
    local BACKUP_DIR="$BACKUP_BASE_DIR/$HOSTNAME"
    local BACKUP_FILE=$(ls -t $BACKUP_DIR/${HOSTNAME}_*.tar.gz | head -n 1)

    if [ -z "$BACKUP_FILE" ]; then
        log_message "WARNING" "${YELLOW}No backup found for ${BLUE}$HOSTNAME${RESET}.${RESET}"
        return 1
    fi

    log_message "INFO" "${BOLD}Testing backup for ${BLUE}$HOSTNAME${RESET} (${BLUE}$BACKUP_FILE${RESET})..."
    tar -tzf $BACKUP_FILE > /dev/null

    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "${GREEN}Backup for ${BLUE}$HOSTNAME${RESET} is valid.${RESET}"
        return 0
    else
        log_message "ERROR" "${RED}Backup for ${BLUE}$HOSTNAME${RESET} is corrupted.${RESET}"
        return 1
    fi
}

# Execução principal do script
START_TIME=$(date +%s)
log_message "INFO" "${BOLD}${BLUE}=== Starting backup process ===${RESET}"

# Executar o checklist antes de continuar
source ./checklist.sh

# Inicializar a variável TEST_RESULTS
TEST_RESULTS=0

# Etapa 1: Deletar backups antigos
log_message "INFO" "${BOLD}${BLUE}=== Step 1: Deleting old backups ===${RESET}"
delete_old_backups

# Etapa 2: Backup do Raspberry Pi 4
log_message "INFO" "${BOLD}${BLUE}=== Step 2: Backing up Raspberry Pi 4 ===${RESET}"
if stop_containers $RPI4_IP; then
    backup $RPI4_IP
    start_containers $RPI4_IP
else
    log_message "ERROR" "${RED}Error stopping containers on ${BLUE}$RPI4_IP${RESET}. Backup aborted.${RESET}"
    send_telegram "Backup failed: Error stopping containers on Raspberry Pi 4."
    exit 1
fi

# Etapa 3: Backup do Raspberry Pi 5 (192.168.0.139)
log_message "INFO" "${BOLD}${BLUE}=== Step 3: Backing up Raspberry Pi 5 (192.168.0.139) ===${RESET}"
if stop_containers $RPI5_1_IP; then
    backup $RPI5_1_IP
    start_containers $RPI5_1_IP
else
    log_message "ERROR" "${RED}Error stopping containers on ${BLUE}$RPI5_1_IP${RESET}. Backup aborted.${RESET}"
    send_telegram "Backup failed: Error stopping containers on Raspberry Pi 5 192.168.0.139"
    exit 1
fi

# Etapa 4: Backup do Raspberry Pi 5 (192.168.0.122)
log_message "INFO" "${BOLD}${BLUE}=== Step 4: Backing up Raspberry Pi 5 (192.168.0.122) ===${RESET}"
if stop_containers $RPI5_2_IP; then
    backup $RPI5_2_IP
    start_containers $RPI5_2_IP
else
    log_message "ERROR" "${RED}Error stopping containers on ${BLUE}$RPI5_2_IP${RESET}. Backup aborted.${RESET}"
    send_telegram "Backup failed: Error stopping containers on Raspberry Pi 5 192.168.0.122"
    exit 1
fi

# Etapa 5: Enviar backups para o OneDrive
log_message "INFO" "${BOLD}${BLUE}=== Step 5: Uploading backups to OneDrive ===${RESET}"
upload_to_onedrive

# Etapa 6: Testar backups
log_message "INFO" "${BOLD}${BLUE}=== Step 6: Testing backups ===${RESET}"
TEST_RESULTS=0
test_backup $RPI4_IP || TEST_RESULTS=1
test_backup $RPI5_1_IP || TEST_RESULTS=1
test_backup $RPI5_2_IP || TEST_RESULTS=1

# Etapa 7: Limpeza condicional
log_message "INFO" "${BOLD}${BLUE}=== Step 7: Cleaning local backups ===${RESET}"

if [ "$TEST_RESULTS" -eq 0 ]; then
    if [ ${#CURRENT_BACKUPS[@]} -eq 0 ]; then
        log_message "WARNING" "${YELLOW}No local backups to delete.${RESET}"
    else
        for BACKUP_FILE in "${CURRENT_BACKUPS[@]}"; do
            if [ -f "$BACKUP_FILE" ]; then
                log_message "INFO" "${BOLD}Deleting local backup: ${BLUE}$BACKUP_FILE${RESET}"
                rm -fr "$BACKUP_FILE" && \
                log_message "SUCCESS" "${GREEN}Deleted ${BLUE}$BACKUP_FILE${RESET}"
            else
                log_message "WARNING" "${YELLOW}Backup file ${BLUE}$BACKUP_FILE${RESET} does not exist.${RESET}"
            fi
        done
    fi
else
    log_message "WARNING" "${YELLOW}Keeping local backups due to test failures.${RESET}"
fi

# Etapa 8: Enviar notificação para o Telegram
log_message "INFO" "${BOLD}${BLUE}=== Step 8: Send Telegram notification ===${RESET}"
if [ "$TEST_RESULTS" -eq 0 ]; then
    send_telegram "Backup completed successfully on $(date)." "$LOG_FILE"
else
    send_telegram "Backup completed with errors. Check logs for details."
fi
log_message "INFO" "${BOLD}${BLUE}=== Backup process completed ===${RESET}"