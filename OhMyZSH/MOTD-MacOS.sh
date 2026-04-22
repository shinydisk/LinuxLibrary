# ~/.MOTD.sh — Banner de lancement "solide" — version améliorée
# Bash/Zsh compatible. Source-le depuis ~/.zshrc :
#   [ -f "$HOME/.MOTD.sh" ] && bash "$HOME/.MOTD.sh"

# ------------- Config -------------
MOTD_TITLE="M4c0S T3rm1n4l"
ENABLE_PUBLIC_IP=true
PUBLIC_IP_CACHE_TTL=3600
ENABLE_WEATHER=true
WEATHER_LOC="Lyon"
NET_TIMEOUT=0.8
BOX_STYLE="unicode"
COUNTDOWN_TARGET="2026-12-31"
COUNTDOWN_LABEL="Fin d'année"
LAST_LOGINS_COUNT=3

# Seuils de couleur pour les barres (%)
WARN_THRESHOLD=60
CRIT_THRESHOLD=80

# ------------- Safe mode + utils -------------
set -Eeuo pipefail

has() { command -v "$1" >/dev/null 2>&1; }
tp()  { tput "$@" 2>/dev/null || true; }

BOLD=$(tp bold);      RESET=$(tp sgr0)
FG_BLUE=$(tp setaf 4);    FG_GREEN=$(tp setaf 2)
FG_YELLOW=$(tp setaf 3);  FG_CYAN=$(tp setaf 6)
FG_MAGENTA=$(tp setaf 5); FG_RED=$(tp setaf 1)
FG_WHITE=$(tp setaf 7)

term_width() { printf '%s' "${COLUMNS:-$(tp cols || echo 80)}"; }

# ------------- Helpers -------------

# Barre colorée selon le pourcentage
draw_bar() {
  local pct=$1 width=24
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar="" i color

  if   (( pct >= CRIT_THRESHOLD )); then color="$FG_RED"
  elif (( pct >= WARN_THRESHOLD )); then color="$FG_YELLOW"
  else                                   color="$FG_GREEN"
  fi

  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty;  i++ )); do bar+="░"; done
  printf "%s[%s]%s %d%%" "$color" "$bar" "$RESET" "$pct"
}

sep() {
  local w i line=""
  w=$(term_width)
  for (( i=0; i<w-2; i++ )); do line+="─"; done
  printf " %s%s%s\n" "$FG_CYAN" "$line" "$RESET"
}

kv() {
  local k="$1" v="$2" c="${3:-$FG_CYAN}"
  printf " %s%s%-14s%s%s%s\n" "$BOLD" "$c" "$k" "$RESET" "$v" "$RESET"
}

# ------------- Infos système -------------
get_local_ip() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    ipconfig getifaddr en0 2>/dev/null \
      || ipconfig getifaddr en1 2>/dev/null \
      || echo "N/A"
  else
    if has ip; then
      ip -4 addr show scope global 2>/dev/null \
        | awk '/inet /{print $2}' | sed 's#/.*##' | head -n1 || echo "N/A"
    elif has ifconfig; then
      ifconfig 2>/dev/null \
        | awk '/inet / && $2!="127.0.0.1"{print $2; exit}' || echo "N/A"
    else echo "N/A"; fi
  fi
}

PUBLIC_IP_CACHE="$HOME/.cache/motd_public_ip"
mkdir -p "$(dirname "$PUBLIC_IP_CACHE")" 2>/dev/null || true

get_public_ip() {
  [[ "$ENABLE_PUBLIC_IP" != true ]] && { echo "Disabled"; return; }
  if [[ -f "$PUBLIC_IP_CACHE" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -f %m "$PUBLIC_IP_CACHE" 2>/dev/null \
      || stat -c %Y "$PUBLIC_IP_CACHE" 2>/dev/null || echo 0) ))
    if (( age < PUBLIC_IP_CACHE_TTL )); then cat "$PUBLIC_IP_CACHE"; return; fi
  fi
  local ip="N/A"
  if has curl; then
    ip=$(curl -s --max-time "$NET_TIMEOUT" https://api.ipify.org 2>/dev/null || true)
  elif has wget; then
    ip=$(wget -q -T "$NET_TIMEOUT" -O - https://api.ipify.org 2>/dev/null || true)
  fi
  [[ -z "$ip" ]] && ip="N/A"
  [[ "$ip" != "N/A" ]] && printf '%s' "$ip" > "$PUBLIC_IP_CACHE"
  echo "$ip"
}

get_uptime() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    uptime 2>/dev/null | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' | xargs
  else
    uptime -p 2>/dev/null | sed 's/^up //' || echo "N/A"
  fi
}

# Disk avec barre colorée — macOS + Linux
get_disk() {
  has df || { echo "N/A"; return; }
  local mount="/"
  # Préférer /System/Volumes/Data sur macOS si dispo
  [[ "$(uname -s)" == "Darwin" ]] && df -h /System/Volumes/Data &>/dev/null \
    && mount="/System/Volumes/Data"

  local line used total pct
  line=$(df -h "$mount" 2>/dev/null | awk 'NR==2')
  used=$(echo "$line" | awk '{print $3}')
  total=$(echo "$line" | awk '{print $2}')
  pct=$(echo "$line" | awk '{gsub(/%/,"",$5); print $5+0}')

  local bar; bar="$(draw_bar "$pct")"
  printf "%s  %s / %s" "$bar" "$used" "$total"
}

# RAM — macOS via vm_stat, Linux via /proc/meminfo
get_ram() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local page_size total_pages used_pages free_pages active inactive wired
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    total_pages=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    total_pages=$(( total_pages / page_size ))

    local vm; vm=$(vm_stat 2>/dev/null)
    active=$(echo "$vm"   | awk '/Pages active/   {gsub(/\./,"",$3); print $3+0}')
    inactive=$(echo "$vm" | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3+0}')
    wired=$(echo "$vm"    | awk '/Pages wired/    {gsub(/\./,"",$4); print $4+0}')

    used_pages=$(( active + inactive + wired ))
    local used_mb total_mb pct
    used_mb=$(( used_pages  * page_size / 1024 / 1024 ))
    total_mb=$(( total_pages * page_size / 1024 / 1024 ))
    pct=$(( used_mb * 100 / (total_mb > 0 ? total_mb : 1) ))

    local bar; bar="$(draw_bar "$pct")"
    printf "%s  %dMB / %dMB" "$bar" "$used_mb" "$total_mb"
  else
    # Linux
    if [[ -f /proc/meminfo ]]; then
      local total avail used pct
      total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
      avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
      used=$(( total - avail ))
      pct=$(( used * 100 / (total > 0 ? total : 1) ))
      local used_mb total_mb
      used_mb=$(( used  / 1024 ))
      total_mb=$(( total / 1024 ))
      local bar; bar="$(draw_bar "$pct")"
      printf "%s  %dMB / %dMB" "$bar" "$used_mb" "$total_mb"
    else
      echo "N/A"
    fi
  fi
}

get_cpu() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null \
      | sed 's/(R)//g;s/(TM)//g;s/  */ /g' || echo "N/A"
  elif [[ -f /proc/cpuinfo ]]; then
    awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo \
      | sed 's/(R)//g;s/(TM)//g;s/  */ /g' || echo "N/A"
  else
    echo "N/A"
  fi
}

get_load() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sysctl -n vm.loadavg 2>/dev/null \
      | awk '{printf "%s %s %s", $2, $3, $4}' || echo "N/A"
  elif [[ -f /proc/loadavg ]]; then
    awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg
  else
    echo "N/A"
  fi
}

# Docker — local uniquement si docker est dispo
get_docker() {
  has docker || return
  # Éviter d'accrocher si le daemon est éteint
  docker info &>/dev/null || { echo "Daemon offline"; return; }
  local running total
  running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  total=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
  printf "%s running / %s total" "$running" "$total"
  if (( running > 0 )); then
    echo ""
    docker ps --format '  {{.Names}}\t{{.Status}}' 2>/dev/null \
      | awk -F'\t' '{printf "  %-24s %s\n", $1, $2}' \
      | head -n 8
  fi
}

# Last logins — fix macOS (format différent de Linux)
get_last_logins() {
  has last || { echo "  N/A"; return; }
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # macOS : user tty host date
    # Colonnes : $1=user $2=tty $3=host $4=day $5=month $6=day_num $7=time $8=year
    last -n "$LAST_LOGINS_COUNT" 2>/dev/null \
      | grep -v '^$' \
      | grep -v '^wtmp\|^reboot\|^shutdown' \
      | awk 'NF>=6 {
          user=$1
          host=($3 ~ /^ttys/ || $3 == "") ? "localhost" : $3
          printf "  %-10s  from %-20s  %s %s %s\n", user, host, $5, $6, $7
        }' \
      | head -n "$LAST_LOGINS_COUNT"
  else
    last -n "$LAST_LOGINS_COUNT" 2>/dev/null \
      | awk 'NF>1 && !/^wtmp/ && !/^reboot/{
          printf "  %-10s  from %-16s  %s %s %s\n", $1, $3, $4, $5, $6
        }' \
      | head -n "$LAST_LOGINS_COUNT"
  fi
}

get_countdown() {
  local now target_ts diff
  now=$(date +%s)
  if [[ "$(uname -s)" == "Darwin" ]]; then
    target_ts=$(date -j -f "%Y-%m-%d" "$COUNTDOWN_TARGET" +%s 2>/dev/null || echo 0)
  else
    target_ts=$(date -d "$COUNTDOWN_TARGET" +%s 2>/dev/null || echo 0)
  fi
  diff=$(( (target_ts - now) / 86400 ))
  if   (( diff > 0  )); then printf "J-%d avant %s"    "$diff" "$COUNTDOWN_LABEL"
  elif (( diff == 0 )); then printf "Aujourd'hui : %s !" "$COUNTDOWN_LABEL"
  else                       printf "%s est passé"      "$COUNTDOWN_LABEL"
  fi
}

get_weather() {
  [[ "$ENABLE_WEATHER" != true ]] && return
  local url="https://wttr.in"
  [[ -n "$WEATHER_LOC" ]] && url="${url}/${WEATHER_LOC}"
  has curl && curl -s --max-time "$NET_TIMEOUT" "${url}?format=3" 2>/dev/null || true
}

get_os() {
  if has sw_vers; then
    printf "macOS %s" "$(sw_vers -productVersion)"
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release; printf "%s %s" "$NAME" "${VERSION_ID:-}"
  else
    uname -sr
  fi
}

# ------------- Banner -------------
draw_box() {
  local title="$1" w inner
  local tl tr bl br horiz vert
  if [[ "$BOX_STYLE" == "ascii" ]]; then
    tl="+"; tr="+"; bl="+"; br="+"; horiz="-"; vert="|"
  else
    tl="╭"; tr="╮"; bl="╰"; br="╯"; horiz="─"; vert="│"
  fi
  w=$(term_width); (( w<40 )) && w=40
  inner=$(( w - 2 ))
  local hline="" i
  for (( i=0; i<inner; i++ )); do hline+="$horiz"; done
  printf "%s%s%s\n" "$tl" "$hline" "$tr"
  local t=" $title "
  local pad=$(( inner - ${#t} ))
  (( pad<0 )) && t="${t:0:inner}" && pad=0
  local l=$(( pad / 2 )) r=$(( pad - pad/2 ))
  printf "%s%*s%s%*s%s\n" "$vert" "$l" "" "$t" "$r" "" "$vert"
  printf "%s%s%s\n" "$bl" "$hline" "$br"
}

banner_big() {
  if has figlet; then
    has lolcat && figlet "$1" | lolcat || figlet "$1"
  else
    draw_box "$1"
  fi
}

# ------------- Main -------------
main() {
  echo ""
  banner_big "$MOTD_TITLE"
  echo ""

  local USERNAME HOST LIP PIP UPT DISK RAM CPU LOAD SHL DAT OSN WTH CDW DOCKER

  USERNAME="$(whoami 2>/dev/null || printf '%s' "$USER")"
  HOST="$(hostname 2>/dev/null | sed 's/\.local//' || uname -n)"
  LIP="$(get_local_ip)"
  PIP="$(get_public_ip)"
  UPT="$(get_uptime)"
  DISK="$(get_disk)"
  RAM="$(get_ram)"
  CPU="$(get_cpu)"
  LOAD="$(get_load)"
  DAT="$(date '+%a %d %b %Y %T')"
  OSN="$(get_os)"
  WTH="$(get_weather || true)"
  CDW="$(get_countdown)"
  DOCKER="$(get_docker || true)"

  kv "User:"        "$USERNAME"              "$FG_BLUE"
  kv "Hostname:"    "$HOST"                  "$FG_GREEN"
  kv "OS:"          "$OSN"                   "$FG_MAGENTA"
  kv "CPU:"         "$CPU"                   "$FG_CYAN"
  kv "Shell:"       "${SHELL##*/}"           "$FG_BLUE"
  kv "Date:"        "$DAT"                   "$FG_MAGENTA"
  sep
  kv "Local IPv4:"  "$LIP"                   "$FG_YELLOW"
  kv "Public IPv4:" "$PIP"                   "$FG_CYAN"
  [[ -n "$WTH" ]] && kv "Weather:"           "$WTH"         "$FG_CYAN"
  sep
  kv "Uptime:"      "$UPT"                   "$FG_GREEN"
  kv "Disk (/):"    "$DISK"                  "$FG_YELLOW"
  kv "RAM:"         "$RAM"                   "$FG_YELLOW"
  kv "Load:"        "$LOAD  (1m 5m 15m)"     "$FG_GREEN"
  sep
  kv "Countdown:"   "$CDW"                   "$FG_RED"
  sep

  if [[ -n "$DOCKER" ]]; then
    printf " %s%sDocker:%s\n" "$BOLD" "$FG_BLUE" "$RESET"
    echo "$DOCKER" | while IFS= read -r line; do
      printf " %s%s%s\n" "$FG_CYAN" "$line" "$RESET"
    done
    sep
  fi

  printf " %s%sLast logins:%s\n" "$BOLD" "$FG_BLUE" "$RESET"
  get_last_logins | while IFS= read -r line; do
    printf " %s%s%s\n" "$FG_BLUE" "$line" "$RESET"
  done
  echo ""
}

main
