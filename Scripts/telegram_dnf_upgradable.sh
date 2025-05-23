#!/bin/bash

#Force l'encodage en UTF8 si mail Fonction
export LANG="fr_FR.UTF-8"

# Configuration du bot Telegram
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"

# Fonction Telegram
send_telegram_message() {
local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        --data-urlencode text="$message"
}



# Vérifier les mises à jour disponibles et filtrer la sortie
updates=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | tail -n +2 | sed -E 's/\[.*\]//g' | sed 's/^/👉 /')
host=$(hostname)

# Vérifier si des mises à jour sont disponibles
if [[ -n "$updates" ]]; then
    # Envoie de la notification sur Telegram
        message="✨ Mises à jour dispo pour $host ✨
        Voici la liste des paquets 📦
        $updates"
        send_telegram_message "$message"
fi

# Check SSH Root : 
ssh=$(grep "opened\|closed\|root" /var/log/auth.log | tail -n 2 | awk {'print $1,$2,$6,$9'})

if [[ -n "$ssh" ]]; then
    # Envoie de la notification sur Telegram
        message="✨ Recap Sessions SSH ✨
        Voici la liste des connexions 💻
        $ssh"
        send_telegram_message "$message"
fi