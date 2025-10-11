#!/bin/bash

#=================================================================
# Script de sauvegarde automatique avec rotation et notifications
# Supporte les sauvegardes locales et distantes (rsync/scp)
#=================================================================

# Configuration
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"
HOSTNAME=$(hostname)
DATE=$(date "+%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/backup_$(date +%Y%m).log"

# Répertoires de sauvegarde
BACKUP_BASE_DIR="/backup"
SOURCE_DIRS=(
    "/etc"
    "/home"
    "/var/www"
    "/opt"
)

# Configuration de rétention (en jours)
RETENTION_DAYS=30

# Configuration rsync distant (optionnel)
REMOTE_BACKUP=false
REMOTE_HOST="backup.example.com"
REMOTE_USER="backup"
REMOTE_PATH="/remote/backup/$HOSTNAME"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Notification Telegram
send_notification() {
    local status="$1"
    local message="$2"
    local emoji=""
    
    case $status in
        "SUCCESS") emoji="✅" ;;
        "ERROR") emoji="❌" ;;
        "WARNING") emoji="⚠️" ;;
        "INFO") emoji="ℹ️" ;;
    esac
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        --data-urlencode text="$emoji <b>BACKUP $status</b> - $HOSTNAME
$message
🕒 $(date '+%Y-%m-%d %H:%M:%S')" \
        -d parse_mode="HTML"
}

# Vérification de l'espace disque
check_disk_space() {
    local backup_dir="$1"
    local required_space_gb="$2"
    
    local available_space=$(df "$backup_dir" | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [ "$available_space" -lt "$required_space_gb" ]; then
        log "ERROR: Espace insuffisant. Requis: ${required_space_gb}GB, Disponible: ${available_space}GB"
        send_notification "ERROR" "Espace disque insuffisant pour la sauvegarde
💾 Disponible: ${available_space}GB
📋 Requis: ${required_space_gb}GB"
        return 1
    fi
    
    return 0
}

# Estimation de la taille
estimate_backup_size() {
    local total_size=0
    
    for source_dir in "${SOURCE_DIRS[@]}"; do
        if [ -d "$source_dir" ]; then
            local size=$(du -sb "$source_dir" 2>/dev/null | awk '{print $1}')
            total_size=$((total_size + size))
        fi
    done
    
    # Conversion en GB avec marge de 20%
    echo $((total_size / 1024 / 1024 / 1024 * 120 / 100))
}

# Nettoyage des anciennes sauvegardes
cleanup_old_backups() {
    log "INFO: Nettoyage des sauvegardes anciennes (>${RETENTION_DAYS} jours)"
    
    find "$BACKUP_BASE_DIR" -name "backup_*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null
    
    local cleaned=$(find "$BACKUP_BASE_DIR" -name "backup_*" -type d -mtime +$RETENTION_DAYS | wc -l)
    if [ "$cleaned" -gt 0 ]; then
        log "INFO: $cleaned anciennes sauvegardes supprimées"
    fi
}

# Sauvegarde locale
perform_local_backup() {
    local backup_dir="$BACKUP_BASE_DIR/backup_$DATE"
    local total_files=0
    local backup_size=0
    local start_time=$(date +%s)
    
    log "INFO: Début de la sauvegarde locale vers $backup_dir"
    
    # Création du répertoire de sauvegarde
    mkdir -p "$backup_dir" || {
        log "ERROR: Impossible de créer le répertoire $backup_dir"
        send_notification "ERROR" "Impossible de créer le répertoire de sauvegarde"
        return 1
    }
    
    # Sauvegarde de chaque répertoire
    for source_dir in "${SOURCE_DIRS[@]}"; do
        if [ -d "$source_dir" ]; then
            local dest_dir="$backup_dir$(dirname "$source_dir")"
            mkdir -p "$dest_dir"
            
            log "INFO: Sauvegarde de $source_dir..."
            
            rsync -av --progress --stats \
                --exclude="*.tmp" \
                --exclude="*.log" \
                --exclude=".cache" \
                --exclude="lost+found" \
                "$source_dir" "$dest_dir/" 2>&1 | tee -a "$LOG_FILE"
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                local files=$(find "$dest_dir/$(basename "$source_dir")" -type f | wc -l)
                total_files=$((total_files + files))
                log "INFO: $source_dir sauvegardé avec succès ($files fichiers)"
            else
                log "ERROR: Échec de la sauvegarde de $source_dir"
                send_notification "ERROR" "Échec de la sauvegarde de $source_dir"
            fi
        else
            log "WARNING: $source_dir n'existe pas, ignoré"
        fi
    done
    
    # Création d'un fichier de métadonnées
    cat > "$backup_dir/backup_info.txt" << EOF
Hostname: $HOSTNAME
Date: $(date)
Source directories: ${SOURCE_DIRS[*]}
Total files: $total_files
Backup duration: $(($(date +%s) - start_time)) seconds
EOF
    
    # Compression de la sauvegarde
    log "INFO: Compression de la sauvegarde..."
    tar -czf "$backup_dir.tar.gz" -C "$BACKUP_BASE_DIR" "backup_$DATE" 2>&1 | tee -a "$LOG_FILE"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        rm -rf "$backup_dir"
        backup_size=$(du -h "$backup_dir.tar.gz" | awk '{print $1}')
        log "INFO: Sauvegarde compressée: $backup_size"
        
        send_notification "SUCCESS" "Sauvegarde locale terminée avec succès
📁 Fichiers: $total_files
💾 Taille: $backup_size
⏱️ Durée: $(($(date +%s) - start_time))s"
        
        return 0
    else
        log "ERROR: Échec de la compression"
        send_notification "ERROR" "Échec de la compression de la sauvegarde"
        return 1
    fi
}

# Sauvegarde distante
perform_remote_backup() {
    if [ "$REMOTE_BACKUP" = true ]; then
        local backup_file="$BACKUP_BASE_DIR/backup_$DATE.tar.gz"
        
        if [ -f "$backup_file" ]; then
            log "INFO: Début de la sauvegarde distante vers $REMOTE_HOST"
            
            scp "$backup_file" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/" 2>&1 | tee -a "$LOG_FILE"
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                log "INFO: Sauvegarde distante terminée avec succès"
                send_notification "SUCCESS" "Sauvegarde distante terminée
🌐 Destination: $REMOTE_HOST
📁 Fichier: backup_$DATE.tar.gz"
                return 0
            else
                log "ERROR: Échec de la sauvegarde distante"
                send_notification "ERROR" "Échec de la sauvegarde distante vers $REMOTE_HOST"
                return 1
            fi
        else
            log "ERROR: Fichier de sauvegarde local introuvable"
            return 1
        fi
    fi
}

# Fonction principale
main() {
    echo -e "${BLUE}🔄 DÉBUT DE LA SAUVEGARDE AUTOMATIQUE${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log "INFO: Début du processus de sauvegarde"
    
    # Vérification des prérequis
    if [ ! -d "$BACKUP_BASE_DIR" ]; then
        mkdir -p "$BACKUP_BASE_DIR" || {
            log "ERROR: Impossible de créer $BACKUP_BASE_DIR"
            exit 1
        }
    fi
    
    # Estimation de l'espace requis
    local estimated_size=$(estimate_backup_size)
    log "INFO: Taille estimée de la sauvegarde: ${estimated_size}GB"
    
    # Vérification de l'espace disque
    if ! check_disk_space "$BACKUP_BASE_DIR" "$estimated_size"; then
        exit 1
    fi
    
    # Nettoyage des anciennes sauvegardes
    cleanup_old_backups
    
    # Sauvegarde locale
    if perform_local_backup; then
        echo -e "${GREEN}✅ Sauvegarde locale réussie${NC}"
        
        # Sauvegarde distante si configurée
        perform_remote_backup
    else
        echo -e "${RED}❌ Échec de la sauvegarde locale${NC}"
        exit 1
    fi
    
    log "INFO: Processus de sauvegarde terminé"
    echo -e "${GREEN}✅ SAUVEGARDE TERMINÉE${NC}"
}

# Vérification des droits root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ce script doit être exécuté en tant que root${NC}"
    exit 1
fi

# Exécution
main "$@"