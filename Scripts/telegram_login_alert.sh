#!/bin/bash

BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"

USER=$(whoami)
IP=$(echo $PAM_RHOST)
DATE=$(date "+%Y/%m/%d %H:%M:%S")
HOSTNAME=$(hostname)

TEXT="🔐 *SSH Connection Detected*
📟 *Hostname* : \`$HOSTNAME\`
👤 *User* : \`$USER\`
🌐 *IP* : \`$(echo ${IP:-locale})\`
🕒 *Time* : \`$DATE\`"

curl -s -X POST https://api.telegram.org/bot${BOT_TOKEN}/sendMessage \
     -d chat_id="${CHAT_ID}" \
     -d text="$TEXT" \
     -d parse_mode="MarkdownV2"