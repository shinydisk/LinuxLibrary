#!/bin/bash

#=================================================================
# Gestionnaire avancé de containers Docker avec monitoring
# Gestion, surveillance et maintenance automatisée
#=================================================================

# Configuration
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"
HOSTNAME=$(hostname)

# Seuils d'alerte
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90

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
        "INFO") emoji="🐳" ;;
    esac
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        --data-urlencode text="$emoji <b>DOCKER $status</b> - $HOSTNAME
<b>$title</b>
$message
🕒 $(date '+%Y-%m-%d %H:%M:%S')" \
        -d parse_mode="HTML"
}

# Vérifier si Docker est installé et en cours d'exécution
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker n'est pas installé${NC}"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo -e "${RED}❌ Docker n'est pas en cours d'exécution${NC}"
        exit 1
    fi
}

# Afficher le statut des containers
show_containers_status() {
    echo -e "${BLUE}🐳 STATUT DES CONTAINERS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local running=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -v NAMES)
    local all_containers=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -v NAMES)
    
    if [ -z "$running" ]; then
        echo -e "${YELLOW}⚠️  Aucun container en cours d'exécution${NC}"
    else
        echo -e "${GREEN}📊 Containers actifs:${NC}"
        echo "$running" | while IFS= read -r line; do
            echo -e "${GREEN}  ✅${NC} $line"
        done
    fi
    
    # Containers arrêtés
    local stopped=$(echo "$all_containers" | grep -v "Up ")
    if [ ! -z "$stopped" ]; then
        echo ""
        echo -e "${RED}📊 Containers arrêtés:${NC}"
        echo "$stopped" | while IFS= read -r line; do
            echo -e "${RED}  ❌${NC} $line"
        done
    fi
}

# Surveiller les ressources des containers
monitor_containers_resources() {
    echo -e "${CYAN}📈 SURVEILLANCE DES RESSOURCES${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local containers=$(docker ps --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        echo -e "${YELLOW}⚠️  Aucun container à surveiller${NC}"
        return
    fi
    
    echo "$containers" | while IFS= read -r container; do
        if [ ! -z "$container" ]; then
            echo -e "${BLUE}📦 Container: $container${NC}"
            
            # Obtenir les statistiques
            local stats=$(docker stats "$container" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}")
            local cpu=$(echo "$stats" | tail -n1 | awk '{print $1}' | tr -d '%')
            local mem_perc=$(echo "$stats" | tail -n1 | awk '{print $3}' | tr -d '%')
            local mem_usage=$(echo "$stats" | tail -n1 | awk '{print $2}')
            local net_io=$(echo "$stats" | tail -n1 | awk '{print $4}')
            local block_io=$(echo "$stats" | tail -n1 | awk '{print $5}')
            
            # Affichage avec couleurs selon les seuils
            if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )); then
                echo -e "  ${RED}🔥 CPU: ${cpu}%${NC} (⚠️ Seuil dépassé)"
                send_notification "WARNING" "CPU élevé détecté" "Container: $container
CPU: ${cpu}%
Seuil: ${CPU_THRESHOLD}%"
            else
                echo -e "  ${GREEN}💻 CPU: ${cpu}%${NC}"
            fi
            
            if (( $(echo "$mem_perc > $MEMORY_THRESHOLD" | bc -l) )); then
                echo -e "  ${RED}🧠 Mémoire: ${mem_usage} (${mem_perc}%)${NC} (⚠️ Seuil dépassé)"
                send_notification "WARNING" "Mémoire élevée détectée" "Container: $container
Mémoire: ${mem_usage} (${mem_perc}%)
Seuil: ${MEMORY_THRESHOLD}%"
            else
                echo -e "  ${GREEN}💾 Mémoire: ${mem_usage} (${mem_perc}%)${NC}"
            fi
            
            echo -e "  ${CYAN}🌐 Réseau: ${net_io}${NC}"
            echo -e "  ${PURPLE}💿 I/O Disque: ${block_io}${NC}"
            echo ""
        fi
    done
}

# Nettoyer les ressources Docker
cleanup_docker() {
    echo -e "${YELLOW}🧹 NETTOYAGE DOCKER${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Images non utilisées
    local unused_images=$(docker images -f "dangling=true" -q)
    if [ ! -z "$unused_images" ]; then
        echo -e "${YELLOW}🗑️  Suppression des images non taguées...${NC}"
        docker rmi $unused_images 2>/dev/null
    fi
    
    # Containers arrêtés
    local stopped_containers=$(docker ps -a -f "status=exited" -q)
    if [ ! -z "$stopped_containers" ]; then
        echo -e "${YELLOW}🗑️  Suppression des containers arrêtés...${NC}"
        docker rm $stopped_containers 2>/dev/null
    fi
    
    # Volumes non utilisés
    echo -e "${YELLOW}🗑️  Suppression des volumes non utilisés...${NC}"
    docker volume prune -f
    
    # Réseaux non utilisés
    echo -e "${YELLOW}🗑️  Suppression des réseaux non utilisés...${NC}"
    docker network prune -f
    
    # Nettoyage système complet
    echo -e "${YELLOW}🗑️  Nettoyage système Docker...${NC}"
    local cleanup_result=$(docker system prune -f)
    
    echo -e "${GREEN}✅ Nettoyage terminé${NC}"
    
    # Notification du nettoyage
    send_notification "SUCCESS" "Nettoyage Docker effectué" "Ressources nettoyées:
$cleanup_result"
}

# Vérifier l'état de santé des containers
check_containers_health() {
    echo -e "${GREEN}🏥 VÉRIFICATION DE SANTÉ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local containers=$(docker ps --format "{{.Names}}")
    
    echo "$containers" | while IFS= read -r container; do
        if [ ! -z "$container" ]; then
            local health=$(docker inspect "$container" --format="{{.State.Health.Status}}" 2>/dev/null)
            local status=$(docker inspect "$container" --format="{{.State.Status}}")
            local restart_count=$(docker inspect "$container" --format="{{.RestartCount}}")
            
            echo -e "${BLUE}📦 $container${NC}"
            
            case $status in
                "running")
                    echo -e "  ${GREEN}✅ Statut: En cours d'exécution${NC}"
                    ;;
                "exited")
                    echo -e "  ${RED}❌ Statut: Arrêté${NC}"
                    send_notification "ERROR" "Container arrêté" "Container: $container
Statut: Arrêté"
                    ;;
                *)
                    echo -e "  ${YELLOW}⚠️  Statut: $status${NC}"
                    ;;
            esac
            
            if [ "$health" != "" ]; then
                case $health in
                    "healthy")
                        echo -e "  ${GREEN}💚 Santé: Sain${NC}"
                        ;;
                    "unhealthy")
                        echo -e "  ${RED}💔 Santé: Non sain${NC}"
                        send_notification "ERROR" "Container non sain" "Container: $container
État de santé: Non sain"
                        ;;
                    *)
                        echo -e "  ${YELLOW}💛 Santé: $health${NC}"
                        ;;
                esac
            fi
            
            if [ "$restart_count" -gt 0 ]; then
                echo -e "  ${YELLOW}🔄 Redémarrages: $restart_count${NC}"
                if [ "$restart_count" -gt 5 ]; then
                    send_notification "WARNING" "Redémarrages multiples détectés" "Container: $container
Nombre de redémarrages: $restart_count"
                fi
            fi
            
            echo ""
        fi
    done
}

# Gérer les containers
manage_containers() {
    local action="$1"
    local container="$2"
    
    case $action in
        "start")
            if [ ! -z "$container" ]; then
                echo -e "${BLUE}🚀 Démarrage du container $container...${NC}"
                if docker start "$container"; then
                    echo -e "${GREEN}✅ Container $container démarré${NC}"
                    send_notification "SUCCESS" "Container démarré" "Container: $container"
                else
                    echo -e "${RED}❌ Échec du démarrage de $container${NC}"
                    send_notification "ERROR" "Échec démarrage container" "Container: $container"
                fi
            fi
            ;;
        "stop")
            if [ ! -z "$container" ]; then
                echo -e "${YELLOW}⏹️  Arrêt du container $container...${NC}"
                if docker stop "$container"; then
                    echo -e "${GREEN}✅ Container $container arrêté${NC}"
                    send_notification "INFO" "Container arrêté" "Container: $container"
                else
                    echo -e "${RED}❌ Échec de l'arrêt de $container${NC}"
                fi
            fi
            ;;
        "restart")
            if [ ! -z "$container" ]; then
                echo -e "${BLUE}🔄 Redémarrage du container $container...${NC}"
                if docker restart "$container"; then
                    echo -e "${GREEN}✅ Container $container redémarré${NC}"
                    send_notification "INFO" "Container redémarré" "Container: $container"
                else
                    echo -e "${RED}❌ Échec du redémarrage de $container${NC}"
                fi
            fi
            ;;
        *)
            echo -e "${RED}❌ Action non reconnue: $action${NC}"
            echo "Actions disponibles: start, stop, restart"
            ;;
    esac
}

# Afficher l'utilisation de l'espace Docker
show_docker_usage() {
    echo -e "${PURPLE}💾 UTILISATION DE L'ESPACE DOCKER${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    docker system df -v
    
    local total_size=$(docker system df | grep "Total" | awk '{print $4}')
    echo ""
    echo -e "${BLUE}📊 Espace total utilisé: $total_size${NC}"
}

# Menu interactif
show_menu() {
    echo -e "${CYAN}🐳 GESTIONNAIRE DOCKER AVANCÉ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. 📊 Afficher le statut des containers"
    echo "2. 📈 Surveiller les ressources"
    echo "3. 🏥 Vérifier la santé des containers"
    echo "4. 🧹 Nettoyer Docker"
    echo "5. 💾 Afficher l'utilisation de l'espace"
    echo "6. 🚀 Démarrer un container"
    echo "7. ⏹️  Arrêter un container"
    echo "8. 🔄 Redémarrer un container"
    echo "9. 📋 Rapport complet"
    echo "0. ❌ Quitter"
    echo ""
    echo -n "Choisissez une option: "
}

# Rapport complet
generate_full_report() {
    clear
    echo -e "${CYAN}📋 RAPPORT COMPLET DOCKER${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    show_containers_status
    echo ""
    monitor_containers_resources
    echo ""
    check_containers_health
    echo ""
    show_docker_usage
    
    # Envoyer un rapport par Telegram
    local running_count=$(docker ps -q | wc -l)
    local total_count=$(docker ps -a -q | wc -l)
    local images_count=$(docker images -q | wc -l)
    
    send_notification "INFO" "Rapport Docker généré" "📊 Containers actifs: $running_count/$total_count
🖼️ Images: $images_count
🖥️ Host: $HOSTNAME"
}

# Fonction principale
main() {
    check_docker
    
    if [ "$1" = "--monitor" ]; then
        # Mode monitoring automatique
        generate_full_report
        exit 0
    fi
    
    if [ "$1" = "--cleanup" ]; then
        # Mode nettoyage automatique
        cleanup_docker
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
                show_containers_status
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            2)
                clear
                monitor_containers_resources
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            3)
                clear
                check_containers_health
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            4)
                clear
                cleanup_docker
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            5)
                clear
                show_docker_usage
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            6)
                clear
                echo "Containers disponibles:"
                docker ps -a --format "{{.Names}}"
                echo ""
                read -p "Nom du container à démarrer: " container_name
                manage_containers "start" "$container_name"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            7)
                clear
                echo "Containers en cours d'exécution:"
                docker ps --format "{{.Names}}"
                echo ""
                read -p "Nom du container à arrêter: " container_name
                manage_containers "stop" "$container_name"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            8)
                clear
                echo "Containers disponibles:"
                docker ps -a --format "{{.Names}}"
                echo ""
                read -p "Nom du container à redémarrer: " container_name
                manage_containers "restart" "$container_name"
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