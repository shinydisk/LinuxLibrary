# ~/.MOTD.sh — Banner de lancement “solide”
# Bash/Zsh compatible. Source-le depuis ~/.bashrc ou ~/.zshrc :
#   [ -f "$HOME/.MOTD.sh" ] && bash "$HOME/.MOTD.sh" || zsh "$HOME/.MOTD.sh"

# ------------- Config -------------
MOTD_TITLE="Be Strong."
ENABLE_PUBLIC_IP=true          # true/false
PUBLIC_IP_CACHE_TTL=3600       # secondes (1h)
ENABLE_WEATHER=false           # wttr.in (rapide mais réseau)
WEATHER_LOC="${CITY:-}"        # vide => auto
NET_TIMEOUT=0.8                # secondes
BOX_STYLE="unicode"            # "unicode" ou "ascii"

# ------------- Safe mode + utils -------------
set -Eeuo pipefail

has() { command -v "$1" >/dev/null 2>&1; }

# tput safe
tp() { tput "$@" 2>/dev/null || true; }

BOLD=$(tp bold); RESET=$(tp sgr0)
FG_BLUE=$(tp setaf 4); FG_GREEN=$(tp setaf 2); FG_YELLOW=$(tp setaf 3); FG_CYAN=$(tp setaf 6); FG_MAGENTA=$(tp setaf 5)

term_width() { printf '%s' "${COLUMNS:-$(tp cols || echo 80)}"; }

center_line() {
  local w pad
  w=$(term_width)
  # strip ANSI for length
  local raw="${1//$'\e'[*([:digit:]);m/}"
  local len=${#raw}
  (( len>=w )) && { printf '%s\n' "$1"; return; }
  pad=$(( (w - len) / 2 ))
  printf "%*s%s\n" "$pad" "" "$1"
}

# ------------- OS / Infos -------------
get_local_ip() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "N/A"
  else
    # Linux
    if has ip; then ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | sed 's#/.*##' | head -n1 || echo "N/A"
    elif has ifconfig; then ifconfig 2>/dev/null | awk '/inet / && $2!="127.0.0.1"{print $2; exit}' || echo "N/A"
    else echo "N/A"; fi
  fi
}

PUBLIC_IP_CACHE="$HOME/.cache/motd_public_ip"
mkdir -p "$(dirname "$PUBLIC_IP_CACHE")" 2>/dev/null || true

get_public_ip() {
  [[ "$ENABLE_PUBLIC_IP" != true ]] && { echo "Disabled"; return; }
  # cache
  if [[ -f "$PUBLIC_IP_CACHE" ]]; then
    local age=$(( $(date +%s) - $(stat -f %m "$PUBLIC_IP_CACHE" 2>/dev/null || stat -c %Y "$PUBLIC_IP_CACHE" 2>/dev/null || echo 0) ))
    if (( age < PUBLIC_IP_CACHE_TTL )); then
      cat "$PUBLIC_IP_CACHE"; return
    fi
  fi
  # fetch with timeout and fallbacks
  local ip="N/A"
  if has curl; then
    ip=$(curl -s --max-time "$NET_TIMEOUT" https://api.ipify.org || true)
    [[ -z "$ip" ]] && ip="N/A"
  elif has wget; then
    ip=$(wget -q -T "$NET_TIMEOUT" -O - https://api.ipify.org || true)
    [[ -z "$ip" ]] && ip="N/A"
  fi
  [[ "$ip" != "N/A" ]] && printf '%s' "$ip" > "$PUBLIC_IP_CACHE"
  echo "$ip"
}

get_uptime() {
  if has uptime; then
    uptime -p 2>/dev/null | sed 's/^up /Up: /' || echo "Up: N/A"
  else
    echo "Up: N/A"
  fi
}

get_disk() {
  if has df; then
    df -h / 2>/dev/null | awk 'NR==2{print "Disk: "$3" / "$2" used ("$5")"}' || echo "Disk: N/A"
  else
    echo "Disk: N/A"
  fi
}

get_shell() {
  echo "${SHELL##*/}"
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

get_weather() {
  [[ "$ENABLE_WEATHER" != true ]] && return
  local url="https://wttr.in"
  [[ -n "$WEATHER_LOC" ]] && url="$url/${WEATHER_LOC}"
  has curl && curl -s --max-time "$NET_TIMEOUT" "$url?format=3" 2>/dev/null || true
}

# ------------- Rendering -------------
draw_box() {
  local w title="$1"
  local left right horiz vert tl tr bl br
  if [[ "$BOX_STYLE" == "ascii" ]]; then
    tl="+"; tr="+"; bl="+"; br="+"; horiz="-"; vert="|"
  else
    tl="╭"; tr="╮"; bl="╰"; br="╯"; horiz="─"; vert="│"
  fi
  w=$(term_width)
  (( w<40 )) && w=40
  local inner=$(( w - 2 ))
  printf "%s%s%s\n" "$tl" "$(printf %${inner}s | tr ' ' "$horiz")" "$tr"
  # Title centered
  local t=" $title "
  local pad=$(( inner - ${#t} ))
  (( pad<0 )) && t="${t:0:inner}" && pad=0
  local l=$(( pad / 2 )); local r=$(( pad - l ))
  printf "%s%*s%s%*s%s\n" "$vert" "$l" "" "$t" "$r" "" "$vert"
  printf "%s%s%s\n" "$bl" "$(printf %${inner}s | tr ' ' "$horiz")" "$br"
}

banner_big() {
  local title="$1"
  if has figlet; then
    if has lolcat; then figlet "$title" | lolcat
    else figlet "$title"
    fi
  else
    draw_box "$title"
  fi
}

kv() {
  # key, value, color
  local k="$1" v="$2" c="${3:-$FG_CYAN}"
  printf " %s%s%s %s%s%s\n" "$BOLD" "$c" "$k" "$RESET" "$v" "$RESET"
}

# ------------- Main -------------
main() {
  local width; width=$(term_width)
  echo ""
  banner_big "$MOTD_TITLE"
  echo ""

  local USERNAME HOST LIP PIP UPT DISK SHL DAT OSN WTH
  USERNAME="$(whoami 2>/dev/null || printf '%s' "$USER")"
  HOST="$(hostname 2>/dev/null || uname -n)"
  LIP="$(get_local_ip)"
  PIP="$(get_public_ip)"
  UPT="$(get_uptime)"
  DISK="$(get_disk)"
  SHL="$(get_shell)"
  DAT="$(date '+%a %d %b %Y %T')"
  OSN="$(get_os)"
  WTH="$(get_weather || true)"

  kv "User:"        "$USERNAME" "$FG_BLUE"
  kv "Hostname:"    "$HOST"     "$FG_GREEN"
  kv "OS:"          "$OSN"      "$FG_MAGENTA"
  kv "Local IPv4:"  "$LIP"      "$FG_YELLOW"
  kv "Public IPv4:" "$PIP"      "$FG_CYAN"
  kv "Uptime:"      "$UPT"      "$FG_GREEN"
  kv "Disk:"        "$DISK"     "$FG_YELLOW"
  kv "Shell:"       "$SHL"      "$FG_BLUE"
  kv "Date:"        "$DAT"      "$FG_MAGENTA"
  [[ -n "$WTH" ]] && kv "Weather:" "$WTH" "$FG_CYAN"

  echo ""
}

main