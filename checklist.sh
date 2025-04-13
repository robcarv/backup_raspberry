#!/bin/bash

# Colors for formatting
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)
BOLD=$(tput bold)

# Function to clean backup directory
clean_backup_dir() {
    echo -e "${BOLD}${BLUE}=== Cleaning backup directory ===${RESET}"
    echo -ne "${BOLD}Cleaning ${BACKUP_BASE_DIR}...${RESET} "
    
    if [ -d "$BACKUP_BASE_DIR" ]; then
        if rm -fr "${BACKUP_BASE_DIR}"/*; then
            echo -e "${GREEN}✔ CLEANED${RESET}"
        else
            echo -e "${RED}✘ FAILED TO CLEAN${RESET}"
            return 1
        fi
    else
        echo -e "${YELLOW}✘ DIRECTORY DOESN'T EXIST${RESET}"
        mkdir -p "$BACKUP_BASE_DIR" && echo -e "${GREEN}✔ CREATED DIRECTORY${RESET}"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    local ALL_CHECKS_PASSED=true

    # Checklist header
    echo -e "${BOLD}${BLUE}=== Running Preflight Checks ===${RESET}"

    # Helper function to display the result of each check
    check_item() {
        local DESCRIPTION=$1
        local COMMAND=$2
        echo -ne "${BOLD}${DESCRIPTION}...${RESET} "
        if eval "$COMMAND" > /dev/null 2>&1; then
            echo -e "${GREEN}✔ OK${RESET}"
        else
            echo -e "${RED}✘ FAILED${RESET}"
            ALL_CHECKS_PASSED=false
        fi
    }

    # Clean backup directory first
    clean_backup_dir || ALL_CHECKS_PASSED=false

    # Check if rclone is installed and configured
    check_item "Checking rclone" "rclone listremotes"

    # Check connection to OneDrive
    check_item "Checking connection to OneDrive" "rclone lsf '$ONEDRIVE_REMOTE'"

    # Check SSH connection to each Raspberry Pi
    check_item "Checking SSH connection to Raspberry Pi 4 ($RPI4_IP)" "ssh -o ConnectTimeout=5 $USER@$RPI4_IP 'exit'"
    check_item "Checking SSH connection to Raspberry Pi 5 ($RPI5_1_IP)" "ssh -o ConnectTimeout=5 $USER@$RPI5_1_IP 'exit'"
    check_item "Checking SSH connection to Raspberry Pi 5 ($RPI5_2_IP)" "ssh -o ConnectTimeout=5 $USER@$RPI5_2_IP 'exit'"

    # Check if Docker is installed and running on each Raspberry Pi
    check_item "Checking Docker on Raspberry Pi 4 ($RPI4_IP)" "ssh $USER@$RPI4_IP 'docker --version'"
    check_item "Checking Docker on Raspberry Pi 5 ($RPI5_1_IP)" "ssh $USER@$RPI5_1_IP 'docker --version'"
    check_item "Checking Docker on Raspberry Pi 5 ($RPI5_2_IP)" "ssh $USER@$RPI5_2_IP 'docker --version'"

    # Check if the local backup directory exists
    check_item "Checking local backup directory ($BACKUP_BASE_DIR)" "[ -d '$BACKUP_BASE_DIR' ]"

    # Check if the log file can be created
    check_item "Checking log file permissions ($LOG_FILE)" "touch '$LOG_FILE'"

    # Check if Telegram is configured correctly
    check_item "Checking Telegram configuration" "curl -s -X POST 'https://api.telegram.org/bot$TELEGRAM_TOKEN/getMe' | grep -q 'ok'"

    # Check Internet connection
    check_item "Checking Internet connection" "ping -c 1 google.com"

    # Check Internet speed (optional, requires speedtest-cli)
    if command -v speedtest-cli &> /dev/null; then
        echo -e "${BOLD}Testing Internet speed...${RESET}"
        speedtest-cli --simple
    else
        echo -e "${YELLOW}${BOLD}speedtest-cli not installed. Skipping speed test.${RESET}"
    fi

    # Check available disk space
    echo -e "${BOLD}Checking disk space...${RESET}"
    df -h "$BACKUP_BASE_DIR"

    # Check if essential commands are installed
    check_item "Checking pv command" "pv --version"
    check_item "Checking tar command" "tar --version"
    check_item "Checking gzip command" "gzip --version"
    check_item "Checking curl command" "curl --version"
    check_item "Checking ssh command" "ssh -V"

    # Display the overall checklist result
    echo -e "${BOLD}${BLUE}=== Checklist Result ===${RESET}"
    if $ALL_CHECKS_PASSED; then
        echo -e "${GREEN}${BOLD}All preflight checks passed successfully!${RESET}"
    else
        echo -e "${RED}${BOLD}Error: One or more preflight checks failed. Please fix the issues before proceeding.${RESET}"
        exit 1
    fi
}

# Run the checklist function
check_prerequisites