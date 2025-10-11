#!/bin/bash

#=================================================================
# Analyseur de logs avancé avec détection d'anomalies
# Surveille les logs système et envoie des alertes intelligentes
#=================================================================

# Configuration
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"
HOSTNAME=$(hostname)
STATE_FILE="/tmp/log_analyzer_state"

# Logs à surveiller
LOG_FILES=(
    "/var/log/auth.log"
    "/var/log/syslog"
    "/var/log/nginx/error.log"
    "/var/log/apache2/error.log"
    "/var/log/fail2ban.log"
)

# Patterns de sécurité critiques
CRITICAL_PATTERNS=(
    "Failed password.*root"
    "POSSIBLE BREAK-IN ATTEMPT"
    "Invalid user.*from"
    "Connection closed by authenticating user root"
    "Accepted publickey for root"
    "sudo.*COMMAND.*rm -rf"
    "kernel:.*segfault"
    "Out of memory"
    "blocked by fail2ban"
)

# Patterns d'erreurs communes
ERROR_PATTERNS=(
    "ERROR"
    "CRITICAL"
    "FATAL"
    "panic"
    "emergency"
    "alert"
)

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Fonction de notification Telegram
send_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local log_file="$4"
    
    local emoji=""
    case $severity in
        "CRITICAL") emoji="🚨" ;;
        "HIGH") emoji="⚠️" ;;
        "MEDIUM") emoji="⚡" ;;
        "LOW") emoji="ℹ️" ;;
    esac
    
    local alert_message="$emoji <b>$severity - $title</b>
🖥️ <b>Host:</b> $HOSTNAME
📁 <b>Log:</b> $(basename "$log_file")
📝 <b>Détails:</b>
<code>$message</code>
🕒 $(date '+%Y-%m-%d %H:%M:%S')"
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        --data-urlencode text="$alert_message" \
        -d parse_mode="HTML"
}

# Obtenir la dernière position de lecture
get_last_position() {
    local log_file="$1"
    local state_key=$(echo "$log_file" | tr '/' '_')
    
    if [ -f "$STATE_FILE" ]; then
        grep "^$state_key:" "$STATE_FILE" | cut -d: -f2
    else
        echo "0"
    fi
}

# Sauvegarder la position de lecture
save_position() {
    local log_file="$1"
    local position="$2"
    local state_key=$(echo "$log_file" | tr '/' '_')
    
    # Créer le fichier d'état s'il n'existe pas
    touch "$STATE_FILE"
    
    # Supprimer l'ancienne entrée et ajouter la nouvelle
    sed -i "/^$state_key:/d" "$STATE_FILE"
    echo "$state_key:$position" >> "$STATE_FILE"
}

# Analyser les tentatives de connexion SSH
analyze_ssh_attempts() {
    local log_file="$1"
    local new_lines="$2"
    
    # Comptage des tentatives échouées par IP
    local failed_attempts=$(echo "$new_lines" | grep -i "failed password" | awk '{print $11}' | sort | uniq -c | sort -nr)
    
    if [ ! -z "$failed_attempts" ]; then
        echo "$failed_attempts" | while read count ip; do
            if [ "$count" -gt 5 ]; then
                send_alert "HIGH" "Attaque par force brute détectée" \
                    "IP: $ip
Tentatives: $count
Logs récents depuis cette IP:" \
                    "$log_file"
                
                # Afficher quelques logs récents de cette IP
                echo "$new_lines" | grep "$ip" | tail -3
            fi
        done
    fi
}

# Analyser les escalades de privilèges
analyze_privilege_escalation() {
    local log_file="$1"
    local new_lines="$2"
    
    local sudo_commands=$(echo "$new_lines" | grep -i "sudo.*COMMAND" | grep -v "systemctl\|service\|ls\|cat\|tail")
    
    if [ ! -z "$sudo_commands" ]; then
        echo "$sudo_commands" | while IFS= read -r line; do
            local user=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="USER=") print $(i+1)}' | tr -d ':')
            local command=$(echo "$line" | awk -F'COMMAND=' '{print $2}')
            
            # Alerter sur les commandes potentiellement dangereuses
            if echo "$command" | grep -qE "(rm -rf|dd|fdisk|mkfs|chmod 777|passwd)"; then
                send_alert "CRITICAL" "Commande potentiellement dangereuse exécutée" \
                    "Utilisateur: $user
Commande: $command" \
                    "$log_file"
            fi
        done
    fi
}

# Analyser les erreurs système
analyze_system_errors() {
    local log_file="$1"
    local new_lines="$2"
    
    # Recherche d'erreurs Out of Memory
    local oom_errors=$(echo "$new_lines" | grep -i "out of memory\|oom-killer\|killed process")
    if [ ! -z "$oom_errors" ]; then
        send_alert "CRITICAL" "Erreur mémoire système détectée" \
            "$oom_errors" \
            "$log_file"
    fi
    
    # Recherche d'erreurs de segmentation
    local segfault_errors=$(echo "$new_lines" | grep -i "segfault\|general protection fault")
    if [ ! -z "$segfault_errors" ]; then
        send_alert "HIGH" "Erreur de segmentation détectée" \
            "$segfault_errors" \
            "$log_file"
    fi
    
    # Recherche d'erreurs de disque
    local disk_errors=$(echo "$new_lines" | grep -iE "i/o error|disk.*error|filesystem.*error")
    if [ ! -z "$disk_errors" ]; then
        send_alert "HIGH" "Erreur disque/filesystem détectée" \
            "$disk_errors" \
            "$log_file"
    fi
}

# Analyser un fichier de log
analyze_log_file() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        return
    fi
    
    echo -e "${BLUE}📋 Analyse de $(basename "$log_file")...${NC}"
    
    # Obtenir la position de la dernière lecture
    local last_pos=$(get_last_position "$log_file")
    local current_pos=$(wc -l < "$log_file")
    
    # Si le fichier a été tronqué ou c'est la première fois
    if [ "$current_pos" -lt "$last_pos" ]; then
        last_pos=0
    fi
    
    # Lire uniquement les nouvelles lignes
    if [ "$current_pos" -gt "$last_pos" ]; then
        local new_lines=$(tail -n +$((last_pos + 1)) "$log_file" | head -n $((current_pos - last_pos)))
        local new_lines_count=$((current_pos - last_pos))
        
        echo -e "${GREEN}  📊 $new_lines_count nouvelles lignes trouvées${NC}"
        
        # Analyser les patterns critiques
        for pattern in "${CRITICAL_PATTERNS[@]}"; do
            local matches=$(echo "$new_lines" | grep -E "$pattern")
            if [ ! -z "$matches" ]; then
                send_alert "CRITICAL" "Pattern critique détecté: $pattern" \
                    "$matches" \
                    "$log_file"
                echo -e "${RED}  🚨 Pattern critique trouvé: $pattern${NC}"
            fi
        done
        
        # Analyser les erreurs communes
        for pattern in "${ERROR_PATTERNS[@]}"; do
            local matches=$(echo "$new_lines" | grep -i "$pattern" | head -5)
            if [ ! -z "$matches" ]; then
                local count=$(echo "$new_lines" | grep -i "$pattern" | wc -l)
                if [ "$count" -gt 10 ]; then
                    send_alert "MEDIUM" "Nombre élevé d'erreurs: $pattern" \
                        "Nombre d'occurrences: $count
Exemples:
$matches" \
                        "$log_file"
                    echo -e "${YELLOW}  ⚠️  Erreurs multiples: $pattern ($count occurrences)${NC}"
                fi
            fi
        done
        
        # Analyses spécialisées
        case $(basename "$log_file") in
            "auth.log")
                analyze_ssh_attempts "$log_file" "$new_lines"
                analyze_privilege_escalation "$log_file" "$new_lines"
                ;;
            "syslog")
                analyze_system_errors "$log_file" "$new_lines"
                ;;
        esac
        
        # Sauvegarder la nouvelle position
        save_position "$log_file" "$current_pos"
        
    else
        echo -e "${GREEN}  ✅ Aucune nouvelle ligne${NC}"
    fi
}

# Générer un rapport de synthèse
generate_summary_report() {
    local total_files=0
    local monitored_files=0
    
    echo -e "${PURPLE}📈 RAPPORT DE SYNTHÈSE${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    for log_file in "${LOG_FILES[@]}"; do
        total_files=$((total_files + 1))
        if [ -f "$log_file" ]; then
            monitored_files=$((monitored_files + 1))
            local size=$(du -h "$log_file" | awk '{print $1}')
            local lines=$(wc -l < "$log_file")
            echo -e "${GREEN}✅${NC} $(basename "$log_file"): $lines lignes ($size)"
        else
            echo -e "${YELLOW}⚠️${NC}  $(basename "$log_file"): fichier non trouvé"
        fi
    done
    
    echo ""
    echo -e "${BLUE}📊 Statistiques:${NC}"
    echo "   • Fichiers surveillés: $monitored_files/$total_files"
    echo "   • Dernière analyse: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "   • Hostname: $HOSTNAME"
}

# Fonction principale
main() {
    clear
    echo -e "${BLUE}🔍 ANALYSEUR DE LOGS AVANCÉ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Analyser chaque fichier de log
    for log_file in "${LOG_FILES[@]}"; do
        analyze_log_file "$log_file"
        echo ""
    done
    
    # Générer le rapport de synthèse
    generate_summary_report
    
    echo ""
    echo -e "${GREEN}✅ Analyse terminée !${NC}"
}

# Vérifier les permissions
if [ ! -r /var/log ]; then
    echo -e "${RED}❌ Permissions insuffisantes pour lire /var/log${NC}"
    echo "Veuillez exécuter ce script avec des privilèges suffisants"
    exit 1
fi

# Mode daemon (optionnel)
if [ "$1" = "--daemon" ]; then
    echo "Mode daemon activé - Analyse toutes les 5 minutes"
    while true; do
        main > /dev/null 2>&1
        sleep 300  # 5 minutes
    done
else
    main
fi