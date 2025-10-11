#!/bin/bash

#=================================================================
# Analyseur de performance réseau avec tests automatisés
# Tests de connectivité, latence, débit et diagnostic réseau
#=================================================================

# Configuration
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"
HOSTNAME=$(hostname)

# Serveurs de test
TEST_SERVERS=(
    "8.8.8.8"           # Google DNS
    "1.1.1.1"           # Cloudflare DNS
    "208.67.222.222"    # OpenDNS
    "google.com"
    "github.com"
    "stackoverflow.com"
)

# Ports communs à tester
COMMON_PORTS=(22 80 443 53 25 110 993 995)

# Seuils d'alerte
PING_THRESHOLD=100      # ms
PACKET_LOSS_THRESHOLD=5 # %
SPEED_THRESHOLD=10      # Mbps

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Notification Telegram
send_notification() {
    local status="$1"
    local title="$2" 
    local message="$3"
    
    local emoji=""
    case $status in
        "SUCCESS") emoji="✅" ;;
        "ERROR") emoji="❌" ;;
        "WARNING") emoji="⚠️" ;;
        "INFO") emoji="🌐" ;;
    esac
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        --data-urlencode text="$emoji <b>RÉSEAU $status</b> - $HOSTNAME
<b>$title</b>
$message
🕒 $(date '+%Y-%m-%d %H:%M:%S')" \
        -d parse_mode="HTML"
}

# Test de ping basique
test_ping() {
    local host="$1"
    local count="${2:-4}"
    
    echo -e "${BLUE}📡 Test de ping vers $host...${NC}"
    
    local ping_result=$(ping -c $count "$host" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        local avg_time=$(echo "$ping_result" | grep "avg" | awk -F'/' '{print $5}' | cut -d' ' -f1)
        local packet_loss=$(echo "$ping_result" | grep "packet loss" | awk '{print $6}' | sed 's/%//')
        
        # Vérification des seuils
        if (( $(echo "$avg_time > $PING_THRESHOLD" | bc -l) )); then
            echo -e "  ${YELLOW}⚠️  Latence élevée: ${avg_time}ms${NC}"
            send_notification "WARNING" "Latence élevée détectée" "Host: $host
Latence: ${avg_time}ms
Seuil: ${PING_THRESHOLD}ms"
        else
            echo -e "  ${GREEN}✅ Latence: ${avg_time}ms${NC}"
        fi
        
        if (( $(echo "$packet_loss > $PACKET_LOSS_THRESHOLD" | bc -l) )); then
            echo -e "  ${RED}❌ Perte de paquets: ${packet_loss}%${NC}"
            send_notification "ERROR" "Perte de paquets détectée" "Host: $host
Perte: ${packet_loss}%
Seuil: ${PACKET_LOSS_THRESHOLD}%"
        else
            echo -e "  ${GREEN}✅ Perte de paquets: ${packet_loss}%${NC}"
        fi
        
        return 0
    else
        echo -e "  ${RED}❌ Échec du ping vers $host${NC}"
        send_notification "ERROR" "Échec de connectivité" "Impossible de joindre: $host"
        return 1
    fi
}

# Test de connectivité de port
test_port_connectivity() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout $timeout bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "  ${GREEN}✅ Port $port ouvert${NC}"
        return 0
    else
        echo -e "  ${RED}❌ Port $port fermé/filtré${NC}"
        return 1
    fi
}

# Test de résolution DNS
test_dns_resolution() {
    local domain="$1"
    
    echo -e "${CYAN}🔍 Test de résolution DNS pour $domain...${NC}"
    
    local start_time=$(date +%s.%N)
    local ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | head -1)
    local end_time=$(date +%s.%N)
    
    if [ ! -z "$ip" ]; then
        local resolution_time=$(echo "$end_time - $start_time" | bc)
        local resolution_ms=$(echo "$resolution_time * 1000" | bc | cut -d. -f1)
        echo -e "  ${GREEN}✅ Résolu en ${resolution_ms}ms: $ip${NC}"
        
        # Test de connectivité vers l'IP résolue
        test_ping "$ip" 2
    else
        echo -e "  ${RED}❌ Échec de résolution DNS${NC}"
        send_notification "ERROR" "Échec résolution DNS" "Domaine: $domain"
    fi
}

# Test de vitesse réseau (approximatif)
test_network_speed() {
    echo -e "${PURPLE}🚀 Test de vitesse réseau...${NC}"
    
    # Test de téléchargement avec curl
    local test_file="http://speedtest.wdc01.softlayer.com/downloads/test10.zip"
    local start_time=$(date +%s)
    
    curl -o /tmp/speedtest.zip -s "$test_file" --max-time 30 2>/dev/null
    local exit_code=$?
    local end_time=$(date +%s)
    
    if [ $exit_code -eq 0 ] && [ -f /tmp/speedtest.zip ]; then
        local file_size=$(stat -f%z /tmp/speedtest.zip 2>/dev/null || stat -c%s /tmp/speedtest.zip)
        local duration=$((end_time - start_time))
        
        if [ $duration -gt 0 ]; then
            local speed_bps=$((file_size / duration))
            local speed_mbps=$(echo "scale=2; $speed_bps / 1024 / 1024 * 8" | bc)
            
            if (( $(echo "$speed_mbps < $SPEED_THRESHOLD" | bc -l) )); then
                echo -e "  ${YELLOW}⚠️  Vitesse faible: ${speed_mbps} Mbps${NC}"
                send_notification "WARNING" "Vitesse réseau faible" "Vitesse: ${speed_mbps} Mbps
Seuil: ${SPEED_THRESHOLD} Mbps"
            else
                echo -e "  ${GREEN}✅ Vitesse: ${speed_mbps} Mbps${NC}"
            fi
        fi
        
        rm -f /tmp/speedtest.zip
    else
        echo -e "  ${RED}❌ Impossible de tester la vitesse${NC}"
    fi
}

# Analyser les interfaces réseau
analyze_network_interfaces() {
    echo -e "${BLUE}🔌 ANALYSE DES INTERFACES RÉSEAU${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    ip addr show | grep -E '^[0-9]+:' | while IFS= read -r line; do
        local interface=$(echo "$line" | awk -F': ' '{print $2}')
        local status=$(echo "$line" | grep -o 'state [A-Z]*' | awk '{print $2}')
        
        echo -e "${CYAN}📡 Interface: $interface${NC}"
        
        case $status in
            "UP")
                echo -e "  ${GREEN}✅ Statut: Actif${NC}"
                ;;
            "DOWN")
                echo -e "  ${RED}❌ Statut: Inactif${NC}"
                ;;
            *)
                echo -e "  ${YELLOW}⚠️  Statut: $status${NC}"
                ;;
        esac
        
        # Obtenir les adresses IP
        local ips=$(ip addr show "$interface" | grep -oE 'inet [0-9.]+/[0-9]+' | awk '{print $2}')
        if [ ! -z "$ips" ]; then
            echo "$ips" | while IFS= read -r ip; do
                echo -e "  ${BLUE}🌐 IP: $ip${NC}"
            done
        fi
        
        # Statistiques de trafic
        local rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null)
        local tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null)
        
        if [ ! -z "$rx_bytes" ] && [ ! -z "$tx_bytes" ]; then
            local rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc)
            local tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc)
            echo -e "  ${GREEN}📥 Reçu: ${rx_mb} MB${NC}"
            echo -e "  ${GREEN}📤 Envoyé: ${tx_mb} MB${NC}"
        fi
        
        echo ""
    done
}

# Vérifier la table de routage
check_routing_table() {
    echo -e "${YELLOW}🗺️  TABLE DE ROUTAGE${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local default_route=$(ip route | grep default)
    if [ ! -z "$default_route" ]; then
        local gateway=$(echo "$default_route" | awk '{print $3}')
        local interface=$(echo "$default_route" | awk '{print $5}')
        
        echo -e "${GREEN}✅ Passerelle par défaut: $gateway via $interface${NC}"
        
        # Test de connectivité vers la passerelle
        echo -e "${BLUE}📡 Test de connectivité vers la passerelle...${NC}"
        test_ping "$gateway" 2
    else
        echo -e "${RED}❌ Aucune passerelle par défaut configurée${NC}"
        send_notification "ERROR" "Problème de routage" "Aucune passerelle par défaut trouvée"
    fi
    
    echo ""
    echo -e "${CYAN}📋 Routes actives:${NC}"
    ip route | head -10 | while IFS= read -r route; do
        echo -e "  ${BLUE}➤${NC} $route"
    done
}

# Test de connectivité complète
run_connectivity_tests() {
    echo -e "${GREEN}🔍 TESTS DE CONNECTIVITÉ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local failed_tests=0
    local total_tests=${#TEST_SERVERS[@]}
    
    for server in "${TEST_SERVERS[@]}"; do
        echo ""
        if ! test_ping "$server" 3; then
            failed_tests=$((failed_tests + 1))
        fi
        
        # Test de résolution DNS pour les domaines
        if [[ ! "$server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            test_dns_resolution "$server"
        fi
    done
    
    echo ""
    echo -e "${BLUE}📊 Résumé des tests:${NC}"
    echo -e "  ${GREEN}✅ Réussis: $((total_tests - failed_tests))/$total_tests${NC}"
    echo -e "  ${RED}❌ Échecs: $failed_tests/$total_tests${NC}"
    
    if [ $failed_tests -gt 0 ]; then
        local success_rate=$(echo "scale=2; ($total_tests - $failed_tests) * 100 / $total_tests" | bc)
        send_notification "WARNING" "Tests de connectivité partiellement échoués" "Taux de réussite: ${success_rate}%
Échecs: $failed_tests/$total_tests"
    fi
}

# Diagnostic réseau complet
run_network_diagnostic() {
    echo -e "${CYAN}🔧 DIAGNOSTIC RÉSEAU COMPLET${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Vérification des services réseau
    echo -e "${BLUE}🔍 Vérification des services réseau...${NC}"
    
    local services=("NetworkManager" "systemd-resolved" "ssh")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✅ $service: actif${NC}"
        else
            echo -e "  ${RED}❌ $service: inactif${NC}"
        fi
    done
    
    echo ""
    
    # Vérification des ports d'écoute
    echo -e "${BLUE}🎧 Ports en écoute:${NC}"
    netstat -tuln 2>/dev/null | grep LISTEN | head -10 | while IFS= read -r line; do
        echo -e "  ${CYAN}🔌${NC} $line"
    done
    
    echo ""
    
    # Vérification des connexions actives
    echo -e "${BLUE}🔗 Connexions actives:${NC}"
    local active_connections=$(netstat -tun 2>/dev/null | grep ESTABLISHED | wc -l)
    echo -e "  ${GREEN}📊 Connexions établies: $active_connections${NC}"
}

# Menu principal
show_menu() {
    echo -e "${CYAN}🌐 ANALYSEUR DE PERFORMANCE RÉSEAU${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. 🔍 Tests de connectivité"
    echo "2. 🚀 Test de vitesse réseau"
    echo "3. 🔌 Analyser les interfaces réseau"
    echo "4. 🗺️  Vérifier la table de routage"
    echo "5. 🔧 Diagnostic réseau complet"
    echo "6. 📡 Test de ping personnalisé"
    echo "7. 🔍 Test de résolution DNS"
    echo "8. 🎯 Test de connectivité de port"
    echo "9. 📋 Rapport complet"
    echo "0. ❌ Quitter"
    echo ""
    echo -n "Choisissez une option: "
}

# Rapport complet
generate_full_report() {
    clear
    echo -e "${CYAN}📋 RAPPORT RÉSEAU COMPLET${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    analyze_network_interfaces
    echo ""
    check_routing_table
    echo ""
    run_connectivity_tests
    echo ""
    test_network_speed
    echo ""
    run_network_diagnostic
    
    # Notification du rapport
    send_notification "INFO" "Rapport réseau généré" "Analyse complète du réseau effectuée
🖥️ Host: $HOSTNAME
📊 Interfaces analysées
🔍 Tests de connectivité effectués"
}

# Fonction principale
main() {
    # Vérifier les outils nécessaires
    for tool in ping dig curl netstat bc; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}❌ Outil manquant: $tool${NC}"
            echo "Veuillez installer les outils nécessaires"
            exit 1
        fi
    done
    
    if [ "$1" = "--full-test" ]; then
        # Mode test complet automatique
        generate_full_report
        exit 0
    fi
    
    # Menu interactif
    while true; do
        clear
        show_menu
        read -r choice
        
        case $choice in
            1)
                clear
                run_connectivity_tests
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            2)
                clear
                test_network_speed
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            3)
                clear
                analyze_network_interfaces
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            4)
                clear
                check_routing_table
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            5)
                clear
                run_network_diagnostic
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            6)
                clear
                read -p "Entrez l'adresse à tester: " target_host
                read -p "Nombre de pings (défaut: 4): " ping_count
                ping_count=${ping_count:-4}
                test_ping "$target_host" "$ping_count"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            7)
                clear
                read -p "Entrez le domaine à résoudre: " domain
                test_dns_resolution "$domain"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            8)
                clear
                read -p "Entrez l'adresse: " target_host
                read -p "Entrez le port: " target_port
                echo -e "${BLUE}Test de connectivité vers $target_host:$target_port...${NC}"
                test_port_connectivity "$target_host" "$target_port"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            9)
                generate_full_report
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            0)
                echo -e "${GREEN}👋 Au revoir !${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Option invalide${NC}"
                sleep 2
                ;;
        esac
    done
}

# Exécution
main "$@"