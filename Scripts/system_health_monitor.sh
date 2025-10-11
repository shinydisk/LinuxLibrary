#!/bin/bash

#=================================================================
# Système de monitoring complet avec notifications Telegram
# Surveille CPU, RAM, Disque, Température et Services
#=================================================================

# Configuration
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"
HOSTNAME=$(hostname)
DATE=$(date "+%Y-%m-%d %H:%M:%S")

# Seuils d'alerte
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
TEMP_THRESHOLD=70

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction d'envoi Telegram
send_telegram_alert() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        --data-urlencode text="$message" \
        -d parse_mode="HTML"
}

# Vérification CPU
check_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    cpu_usage=${cpu_usage%.*}
    
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        echo -e "${RED}⚠️  CPU: ${cpu_usage}%${NC}"
        send_telegram_alert "🔥 <b>ALERTE CPU</b> sur $HOSTNAME
📊 Usage: <b>${cpu_usage}%</b> (seuil: ${CPU_THRESHOLD}%)
🕒 $DATE"
    else
        echo -e "${GREEN}✅ CPU: ${cpu_usage}%${NC}"
    fi
}

# Vérification RAM
check_memory() {
    local mem_info=$(free | grep Mem)
    local total=$(echo $mem_info | awk '{print $2}')
    local used=$(echo $mem_info | awk '{print $3}')
    local mem_percentage=$((used * 100 / total))
    
    if [ "$mem_percentage" -gt "$MEMORY_THRESHOLD" ]; then
        echo -e "${RED}⚠️  RAM: ${mem_percentage}%${NC}"
        send_telegram_alert "🧠 <b>ALERTE MÉMOIRE</b> sur $HOSTNAME
📊 Usage: <b>${mem_percentage}%</b> (seuil: ${MEMORY_THRESHOLD}%)
💾 ${used}K/${total}K utilisés
🕒 $DATE"
    else
        echo -e "${GREEN}✅ RAM: ${mem_percentage}%${NC}"
    fi
}

# Vérification disque
check_disk() {
    df -h | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $1 " " $6 }' | while read output;
    do
        usage=$(echo $output | awk '{ print $1}' | sed 's/%//g')
        partition=$(echo $output | awk '{ print $2 }')
        mount=$(echo $output | awk '{ print $3 }')
        
        if [ $usage -ge $DISK_THRESHOLD ]; then
            echo -e "${RED}⚠️  Disque $mount: ${usage}%${NC}"
            send_telegram_alert "💾 <b>ALERTE DISQUE</b> sur $HOSTNAME
📂 Partition: <b>$mount</b>
📊 Usage: <b>${usage}%</b> (seuil: ${DISK_THRESHOLD}%)
💿 Device: $partition
🕒 $DATE"
        else
            echo -e "${GREEN}✅ Disque $mount: ${usage}%${NC}"
        fi
    done
}

# Vérification température (si sensors est installé)
check_temperature() {
    if command -v sensors &> /dev/null; then
        local temp=$(sensors | grep -i "core 0" | awk '{print $3}' | sed 's/+//g' | sed 's/°C//g' | cut -d. -f1)
        
        if [ ! -z "$temp" ] && [ "$temp" -gt "$TEMP_THRESHOLD" ]; then
            echo -e "${RED}⚠️  Température: ${temp}°C${NC}"
            send_telegram_alert "🌡️ <b>ALERTE TEMPÉRATURE</b> sur $HOSTNAME
🔥 Température: <b>${temp}°C</b> (seuil: ${TEMP_THRESHOLD}°C)
🕒 $DATE"
        else
            echo -e "${GREEN}✅ Température: ${temp}°C${NC}"
        fi
    fi
}

# Vérification des services critiques
check_services() {
    local services=("ssh" "nginx" "apache2" "mysql" "docker")
    local failed_services=""
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}✅ Service $service: actif${NC}"
        else
            # Vérifier si le service existe avant de le signaler comme défaillant
            if systemctl list-unit-files --type=service | grep -q "^$service"; then
                echo -e "${RED}⚠️  Service $service: inactif${NC}"
                failed_services+="• $service\n"
            fi
        fi
    done
    
    if [ ! -z "$failed_services" ]; then
        send_telegram_alert "🔧 <b>SERVICES DÉFAILLANTS</b> sur $HOSTNAME
$failed_services
🕒 $DATE"
    fi
}

# Rapport de santé système
generate_health_report() {
    local uptime=$(uptime | awk -F'( |,|:)+' '{print $6,$7",",$8,"hours,",$9,"minutes"}')
    local load=$(uptime | awk -F'load average:' '{print $2}')
    local processes=$(ps aux | wc -l)
    
    echo "📋 RAPPORT DE SANTÉ SYSTÈME - $HOSTNAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🕒 Date: $DATE"
    echo "⏱️  Uptime: $uptime"
    echo "📊 Load average:$load"
    echo "🔄 Processus actifs: $processes"
    echo ""
}

# Fonction principale
main() {
    clear
    generate_health_report
    
    echo "🔍 Vérification en cours..."
    echo ""
    
    check_cpu
    check_memory
    check_disk
    check_temperature
    check_services
    
    echo ""
    echo "✅ Vérification terminée !"
}

# Exécution
main