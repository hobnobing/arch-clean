#!/usr/bin/env bash

set -euo pipefail

CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")

if [ "$EUID" -ne 0 ]; then
  echo "Run as sudo."
  exit 1
fi

run_with_dots() {
  local title="$1"
  shift
  local cmd=("$@")

  "${cmd[@]}" &>/dev/null &
  local pid=$!

  local frame=0
  local dots=(".  " ".. " "...")

  echo -ne "${WHITE}${title}${NC}"
  while kill -0 "$pid" 2>/dev/null; do
    echo -ne "\r${WHITE}${title}${dots[$frame]}${NC}"
    frame=$(( (frame + 1) % 3 ))
    sleep 0.3
  done

  wait "$pid" || true
  echo -e "\r${WHITE}${title}...${NC} ${GREEN}Done.${NC}"
}

echo -e "${CYAN}Arch Clean${NC}\n"

# 1. Remove orphan packages
ORPHANS=$(pacman -Qtdq 2>/dev/null || true)
if [ -n "$ORPHANS" ]; then
    # Read into array to safely pass to pacman
    mapfile -t ORPHAN_ARRAY <<< "$ORPHANS"
    run_with_dots "[1/9] Removing orphan packages" pacman -Rns --noconfirm "${ORPHAN_ARRAY[@]}"
else
    run_with_dots "[1/9] Checking orphan packages" true
fi

# 2. Pacman cache cleanup
run_with_dots "[2/9] Cleaning Pacman cache" bash -c \
  "rm -rf /var/cache/pacman/pkg/download-* /var/cache/pacman/pkg/*.part 2>/dev/null || true; paccache -r -k2; paccache -ruk0"

# 3. Clean AUR helper caches
if command -v yay &> /dev/null; then
    run_with_dots "[3/9] Cleaning yay cache ($REAL_USER)" runuser -u "$REAL_USER" -- yay -Sc --aur --noconfirm
elif command -v paru &> /dev/null; then
    run_with_dots "[3/9] Cleaning paru cache ($REAL_USER)" runuser -u "$REAL_USER" -- paru -Sc --aur --noconfirm
else
    run_with_dots "[3/9] Checking for AUR helpers" true
fi

# 4. Vacuum systemd journal logs
run_with_dots "[4/9] Vacuuming systemd logs older than 2 weeks" journalctl --vacuum-time=2w

# 5. Clear systemd coredumps
run_with_dots "[5/9] Removing systemd coredumps" bash -c "rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true"

# 6. Clean Flatpak and Docker
if command -v flatpak &> /dev/null; then
    run_with_dots "[6/9] Cleaning Flatpak leftovers" flatpak uninstall --unused --noninteractive
fi

if command -v docker &> /dev/null; then
    # Removed --volumes flag to prevent accidental user data loss
    run_with_dots "[6/9] Pruning Docker assets" docker system prune -af
fi

# 7. User cache cleanup (Fixed globbing & array handling)
run_with_dots "[7/9] Cleaning user cache targets for $REAL_USER" runuser -u "$REAL_USER" -- bash -c '
USER_CACHE_DIRS=(
    "$HOME/.local/share/Trash"
    "$HOME/.cache/thumbnails"
    "$HOME/.cache/pip"
    "$HOME/.cache/go-build"
    "$HOME/.cache/yarn"
    "$HOME/.npm/_cacache"
    "$HOME/.cargo/registry/cache"
)
for target in "${USER_CACHE_DIRS[@]}"; do
    if [ -d "$target" ]; then
        rm -rf "${target:?}"/* 2>/dev/null || true
    fi
done'

# 8. Clean broken symlinks
run_with_dots "[8/9] Cleaning broken symlinks in /var" bash -c \
  "find /var -type l ! -exec test -e {} \; -delete 2>/dev/null || true"

# 9. Check for unmerged .pacnew and .pacsave files
if command -v pacdiff &> /dev/null; then
    PACFILES=$(PACMAN_OUTPUT=1 pacdiff -l 2>/dev/null || true)
    run_with_dots "[9/9] Checking for unmerged configuration files (.pacnew / .pacsave)" true
    if [ -n "$PACFILES" ]; then
        echo -e "${YELLOW}WARNING: Unmerged configuration files detected:${NC}"
        echo "$PACFILES"
        echo "Run 'pacdiff' manually after this script finishes to merge them."
    fi
else
    run_with_dots "[9/9] Checking for pacdiff utility (pacman-contrib missing)" true
fi

# Display storage
echo -e "\n${YELLOW}Storage Summary:${NC}"
df -h /

echo -e "\n${GREEN}Arch Clean Complete${NC}"
