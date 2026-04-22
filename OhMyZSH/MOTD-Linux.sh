# ~/.MOTD.sh — Rocky Linux Docker Host
# Source depuis ~/.bashrc :
#   [ -f "$HOME/.MOTD.sh" ] && bash "$HOME/.MOTD.sh"

# ------------- Config -------------
MOTD_TITLE="R0cky H0st"
ENABLE_PUBLIC_IP=true
PUBLIC_IP_CACHE_TTL=3600
ENABLE_WEATHER=false
WEATHER_LOC=""
NET_TIMEOUT=0.8
BOX_STYLE="unicode"
COUNTDOWN_TARGET="2026-12-31"
COUNTDOWN_LABEL="Fin d'année"
LAST_LOGINS_COUNT=3

# ------------- Safe mode + utils -------------
set -Eeuo pipefail

has() { command -v "$1" >/dev/null 2>&1; }
tp()  { tput "$@" 2>/dev/null || true; }

BOLD=$(tp bold);      RESET=$(tp sgr0)
FG_BLUE=$(tp setaf 4);    FG_GREEN=$(tp setaf 2)
FG_YELLOW=$(tp setaf 3);  FG_CYAN=$(tp setaf 6)
FG_MAGENTA=$(tp setaf 5); FG_RED=$(tp setaf 1)

term_width() { printf '%s' "${COLUMNS:-$(tp cols || echo 80)}"; }

# ------------- Helpers -------------
draw_bar() {
  local pct=$1 width=24
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar="" i
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty;  i++ )); do bar+="░"; done
  printf "[%s] %d%%" "$bar" "$pct"
}

sep() {
  local w i line=""
  w=$(term_width)
  for (( i=0; i<w-2; i++ )); do line+="─"; done
  printf " %s%s%s\n" "$FG_CYAN" "$line" "$RESET"
}

kv() {
  local k="$1" v="$2" c="${3:-$FG_CYAN}"
  printf " %s%s%s %s%s%s\n" "$BOLD" "$c" "$k" "$RESET" "$v" "$RESET"
}

# ------------- Infos système -------------
get_local_ip() {
  if has ip; then
    ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | sed 's#/.*##' | head -n1 || echo "N/A"
  elif has ifconfig; then
    ifconfig 2>/dev/null | awk '/inet / && $2!="127.0.0.1"{print $2; exit}' || echo "N/A"
  else
    echo "N/A"
  fi
}

PUBLIC_IP_CACHE="$HOME/.cache/motd_public_ip"
mkdir -p "$(dirname "$PUBLIC_IP_CACHE")" 2>/dev/null || true

get_public_ip() {
  [[ "$ENABLE_PUBLIC_IP" != true ]] && { echo "Disabled"; return; }
  if [[ -f "$PUBLIC_IP_CACHE" ]]; then
    local age=$(( $(date +%s) - $(stat -c %Y "$PUBLIC_IP_CACHE" 2>/dev/null || echo 0) ))
    if (( age < PUBLIC_IP_CACHE_TTL )); then cat "$PUBLIC_IP_CACHE"; return; fi
  fi
  local ip="N/A"
  if has curl; then
    ip=$(curl -s --max-time "$NET_TIMEOUT" https://api.ipify.org 2>/dev/null || true)
    [[ -z "$ip" ]] && ip="N/A"
  elif has wget; then
    ip=$(wget -q -T "$NET_TIMEOUT" -O - https://api.ipify.org 2>/dev/null || true)
    [[ -z "$ip" ]] && ip="N/A"
  fi
  [[ "$ip" != "N/A" ]] && printf '%s' "$ip" > "$PUBLIC_IP_CACHE"
  echo "$ip"
}

get_uptime() {
  uptime -p 2>/dev/null | sed 's/^up //' || echo "N/A"
}

get_disk() {
  local mount="${1:-/}"
  if has df; then
    local used total pct
    read -r used total pct <<< "$(df -h "$mount" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $3, $2, $5}')"
    local bar; bar="$(draw_bar "${pct:-0}")"
    printf "%s  %s / %s" "$bar" "$used" "$total"
  else
    echo "N/A"
  fi
}

get_ram() {
  if has free; then
    local used total pct
    read -r used total <<< "$(free -m 2>/dev/null | awk '/^Mem:/{print $3, $2}')"
    (( total > 0 )) && pct=$(( used * 100 / total )) || pct=0
    local bar; bar="$(draw_bar "$pct")"
    printf "%s  %dMB / %dMB" "$bar" "$used" "$total"
  else
    echo "N/A"
  fi
}

get_load() {
  if [[ -f /proc/loadavg ]]; then
    awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg
  else
    echo "N/A"
  fi
}

# --- Docker spécifique ---
get_docker() {
  if has docker; then
    local running total
    running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    total=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
    printf "%s running / %s total" "$running" "$total"
  else
    echo "N/A (docker not found)"
  fi
}

get_docker_list() {
  if has docker; then
    docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null \
      | awk '{printf "  %-20s %-25s %s\n", $1, $2" "$3, $4}' \
      | head -n 10 || true
  fi
}

get_last_logins() {
  if has last; then
    last -n "$LAST_LOGINS_COUNT" 2>/dev/null \
      | awk 'NF>1 && !/^wtmp/ && !/^reboot/{printf "  %-10s  from %-16s  %s %s %s\n", $1, $3, $4, $5, $6}' \
      | head -n "$LAST_LOGINS_COUNT" || true
  else
    echo "  N/A"
  fi
}

get_countdown() {
  local now target_ts diff
  now=$(date +%s)
  target_ts=$(date -d "$COUNTDOWN_TARGET" +%s 2>/dev/null || echo 0)
  diff=$(( (target_ts - now) / 86400 ))
  if (( diff > 0 ));    then printf "J-%d avant %s" "$diff" "$COUNTDOWN_LABEL"
  elif (( diff == 0 )); then printf "Aujourd'hui : %s !" "$COUNTDOWN_LABEL"
  else                       printf "%s est passé" "$COUNTDOWN_LABEL"
  fi
}

get_weather() {
  [[ "$ENABLE_WEATHER" != true ]] && return
  local url="https://wttr.in"
  [[ -n "$WEATHER_LOC" ]] && url="${url}/${WEATHER_LOC}"
  has curl && curl -s --max-time "$NET_TIMEOUT" "${url}?format=3" 2>/dev/null || true
}

get_os() {
  if [[ -f /etc/os-release ]]; then
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
    has lolcat && figlet -f slant "$1" | lolcat || figlet -f slant "$1"
  else
    draw_box "$1"
  fi
}

# ------------- Main -------------
main() {
  echo ""
  banner_big "$MOTD_TITLE"
  echo ""

  local USERNAME HOST LIP PIP UPT DISK_ROOT DISK_HOME RAM LOAD SHL DAT OSN WTH CDW DOCK

  USERNAME="$(whoami 2>/dev/null || printf '%s' "$USER")"
  HOST="$(hostname 2>/dev/null || uname -n)"
  LIP="$(get_local_ip)"
  PIP="$(get_public_ip)"
  UPT="$(get_uptime)"
  DISK_ROOT="$(get_disk /)"
  DISK_HOME="$(get_disk /home)"
  RAM="$(get_ram)"
  LOAD="$(get_load)"
  DAT="$(date '+%a %d %b %Y %T')"
  OSN="$(get_os)"
  WTH="$(get_weather || true)"
  CDW="$(get_countdown)"
  DOCK="$(get_docker)"

  kv "User:"        "$USERNAME"  "$FG_BLUE"
  kv "Hostname:"    "$HOST"      "$FG_GREEN"
  kv "OS:"          "$OSN"       "$FG_MAGENTA"
  kv "Shell:"       "${SHELL##*/}" "$FG_BLUE"
  kv "Date:"        "$DAT"       "$FG_MAGENTA"
  sep
  kv "Local IPv4:"  "$LIP"       "$FG_YELLOW"
  kv "Public IPv4:" "$PIP"       "$FG_CYAN"
  [[ -n "$WTH" ]] && kv "Weather:" "$WTH" "$FG_CYAN"
  sep
  kv "Uptime:"      "$UPT"       "$FG_GREEN"
  kv "Disk (/):"    "$DISK_ROOT" "$FG_YELLOW"
  kv "Disk (/home):" "$DISK_HOME" "$FG_YELLOW"
  kv "RAM:"         "$RAM"       "$FG_CYAN"
  kv "Load:"        "$LOAD  (1m 5m 15m)" "$FG_GREEN"
  sep
  kv "Docker:"      "$DOCK"      "$FG_CYAN"
  printf " %s%sContainers:%s\n" "$BOLD" "$FG_CYAN" "$RESET"
  get_docker_list | while IFS= read -r line; do
    printf " %s%s%s\n" "$FG_CYAN" "$line" "$RESET"
  done
  sep
  kv "Countdown:"   "$CDW"       "$FG_RED"
  sep
  printf " %s%sLast logins:%s\n" "$BOLD" "$FG_BLUE" "$RESET"
  get_last_logins | while IFS= read -r line; do
    printf " %s%s%s\n" "$FG_BLUE" "$line" "$RESET"
  done
  echo ""
}

main