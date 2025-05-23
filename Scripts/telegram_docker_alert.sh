#!/bin/bash

BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"

containers=("portainer_agent" "mc" "vaultwarden" "npm_app" "npm_db" "pwpush")

for container in "${containers[@]}"; do
    STATUS=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)

    if [[ "$STATUS" != "running" ]]; then
        MESSAGE="❌ *Alerte conteneur* : \`$container\`
État actuel : \`$STATUS\`
🕒 $(date '+%Y-%m-%d %H:%M:%S')
📟 Hôte : \`$(hostname)\`"

        curl -s -X POST https://api.telegram.org/bot${BOT_TOKEN}/sendMessage \
             -d chat_id="${CHAT_ID}" \
             -d text="$MESSAGE" \
             -d parse_mode="MarkdownV2"
    fi
done