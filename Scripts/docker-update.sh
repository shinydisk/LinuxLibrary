#!/bin/bash
# =============================================================================
# docker-update.sh — Mise à jour automatique des stacks Docker Compose
# Dossier de base : /opt/docker
# Usage : ./docker-update.sh [--dry-run]
# Requires : JetBrainsMono Nerd Font
# =============================================================================

set -euo pipefail

DOCKER_BASE="/opt/docker"
LOG_FILE="/var/log/docker-update.log"
DRY_RUN=false
UPDATED=()
FAILED=()
SKIPPED=()
START_TIME=$(date +%s)

# ── Palette Synthwave ────────────────────────────────────────────────────────
PURPLE='\033[38;5;135m'    # violet
PINK='\033[38;5;213m'      # rose vif
MAGENTA='\033[38;5;165m'   # magenta
CYAN='\033[38;5;117m'      # cyan doux
YELLOW='\033[38;5;228m'    # jaune chaud
GREEN='\033[38;5;156m'     # vert néon
RED='\033[38;5;204m'       # rouge/rose
GRAY='\033[38;5;240m'      # gris sombre
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Icônes Nerd Font ─────────────────────────────────────────────────────────
ICO_DOCKER=""        # nf-dev-docker
ICO_CHECK=""         # nf-fa-check
ICO_CROSS=""         # nf-fa-times
ICO_WARN=""          # nf-fa-warning
ICO_PULL=""          # nf-fa-download
ICO_ROCKET=""        # nf-fa-rocket
ICO_SKIP=""          # nf-fa-minus_circle
ICO_BROOM=""         # nf-fa-trash
ICO_CLOCK=""         # nf-fa-clock_o
ICO_BOLT=""          # nf-fa-bolt
ICO_INFO=""          # nf-fa-info_circle
ICO_DRY=""           # nf-fa-flask
ICO_STACK=""         # nf-fa-cube
ICO_SUMMARY=""       # nf-fa-list_alt

# ── Helpers ──────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
}

line_thin() {
    echo -e "${GRAY}  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌${NC}"
}

line_thick() {
    echo -e "${PURPLE}  ══════════════════════════════════════════════${NC}"
}

# ── Header ───────────────────────────────────────────────────────────────────
print_header() {
    echo ""
    line_thick
    echo -e "${PURPLE}  ║${NC}  ${PINK}${BOLD}${ICO_DOCKER}  Docker Compose — Update Manager${NC}         ${PURPLE}║${NC}"
    echo -e "${PURPLE}  ║${NC}  ${GRAY}$(LC_ALL=en_US.UTF-8 date '+%A %d %B %Y  %H:%M:%S')${NC}       ${PURPLE}║${NC}"
    line_thick
    echo ""

    if $DRY_RUN; then
        echo -e "  ${YELLOW}${BOLD}${ICO_DRY}  Dry-run mode — no changes will be made${NC}"
        echo ""
    fi
}

# ── Pull & détection de mise à jour ──────────────────────────────────────────
pull_images() {
    local dir="$1"
    local output
    output=$(docker compose -f "$dir/docker-compose.yml" pull 2>&1)
    echo "$output" >> "$LOG_FILE"
    echo "$output" | grep -qE "Pull complete|Downloaded newer image"
}

# ── Mise à jour d'une stack ───────────────────────────────────────────────────
update_stack() {
    local name="$1"
    local dir="$DOCKER_BASE/$name"
    local compose_file="$dir/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        compose_file="$dir/docker-compose.yaml"
    fi

    # ── En-tête de la stack
    echo -e "  ${MAGENTA}${BOLD}${ICO_STACK}  ${name}${NC}"
    line_thin

    if [[ ! -f "$compose_file" ]]; then
        echo -e "  ${YELLOW}  ${ICO_WARN}  No compose file found — skipped${NC}"
        log "WARN" "$name: no docker-compose.yml found"
        SKIPPED+=("$name")
        echo ""
        return
    fi

    if $DRY_RUN; then
        echo -e "  ${CYAN}  ${ICO_DRY}  Pull simulated${NC}"
        echo -e "  ${CYAN}  ${ICO_DRY}  Restart simulated${NC}"
        log "INFO" "$name: dry-run"
        echo ""
        return
    fi

    # ── Pull
    echo -e "  ${CYAN}  ${ICO_PULL}  Checking for updates...${NC}"
    log "INFO" "$name: pulling images"

    if pull_images "$dir"; then
        echo -e "  ${GREEN}  ${ICO_BOLT}  New image available!${NC}"
        echo -e "  ${PINK}  ${ICO_ROCKET}  Restarting stack...${NC}"
        log "INFO" "$name: new image detected — restarting"

        if docker compose -f "$compose_file" up -d --remove-orphans >> "$LOG_FILE" 2>&1; then
            echo -e "  ${GREEN}  ${ICO_CHECK}  Stack restarted successfully${NC}"
            log "INFO" "$name: restarted successfully"
            UPDATED+=("$name")
        else
            echo -e "  ${RED}  ${ICO_CROSS}  Restart failed${NC}"
            log "ERROR" "$name: restart failed"
            FAILED+=("$name")
        fi
    else
        echo -e "  ${GRAY}  ${ICO_CHECK}  Already up to date${NC}"
        log "INFO" "$name: already up to date"
    fi

    echo ""
}

# ── Nettoyage ─────────────────────────────────────────────────────────────────
cleanup_images() {
    echo -e "  ${MAGENTA}${BOLD}${ICO_BROOM}  Cleaning up orphaned images${NC}"
    line_thin
    log "INFO" "Cleaning up unused Docker images"

    if $DRY_RUN; then
        echo -e "  ${CYAN}  ${ICO_DRY}  Cleanup simulated${NC}"
    else
        local freed
        freed=$(docker image prune -f 2>>"$LOG_FILE" | grep "reclaimed" || echo "nothing to remove")
        echo -e "  ${GREEN}  ${ICO_CHECK}  $freed${NC}"
        log "INFO" "Cleanup: $freed"
    fi
    echo ""
}

# ── Résumé ────────────────────────────────────────────────────────────────────
print_summary() {
    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - START_TIME))

    line_thick
    echo -e "${PURPLE}  ║${NC}  ${PINK}${BOLD}${ICO_SUMMARY}  Summary${NC}"
    line_thick

    echo -e "  ${CYAN}  ${ICO_CLOCK}  Total duration: ${BOLD}${elapsed}s${NC}"
    echo ""

    if [[ ${#UPDATED[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}  ${ICO_ROCKET}  Updated      (${#UPDATED[@]}) :${NC}"
        for s in "${UPDATED[@]}"; do
            echo -e "  ${GREEN}       ${ICO_CHECK}  $s${NC}"
        done
        echo ""
    fi

    if [[ ${#SKIPPED[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}  ${ICO_SKIP}  Skipped      (${#SKIPPED[@]}) :${NC}"
        for s in "${SKIPPED[@]}"; do
            echo -e "  ${YELLOW}       ${ICO_WARN}  $s${NC}"
        done
        echo ""
    fi

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo -e "  ${RED}  ${ICO_CROSS}  Failed       (${#FAILED[@]}) :${NC}"
        for s in "${FAILED[@]}"; do
            echo -e "  ${RED}       ${ICO_CROSS}  $s${NC}"
        done
        echo ""
    fi

    if [[ ${#UPDATED[@]} -eq 0 && ${#FAILED[@]} -eq 0 ]]; then
        echo -e "  ${GRAY}  ${ICO_INFO}  All stacks are already up to date${NC}"
        echo ""
    fi

    line_thick
    echo ""
    log "INFO" "Finished in ${elapsed}s — updated: [${UPDATED[*]:-none}] | failed: [${FAILED[*]:-none}]"
}

# =============================================================================
# Point d'entrée
# =============================================================================

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if ! command -v docker &>/dev/null; then
    echo -e "${RED}${ICO_CROSS}  Error: docker is not installed or not in PATH${NC}" >&2
    exit 1
fi

if [[ ! -d "$DOCKER_BASE" ]]; then
    echo -e "${RED}${ICO_CROSS}  Error: directory $DOCKER_BASE does not exist${NC}" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

print_header
log "INFO" "=== Update started ==="

STACKS=(
    portainer_agent
    npm
    vaultwarden
    navidrome
    pwpush
    mc
    monitoring
)

for stack in "${STACKS[@]}"; do
    update_stack "$stack"
done

cleanup_images
print_summary

[[ ${#FAILED[@]} -eq 0 ]] && exit 0 || exit 1
