set -euo pipefail

CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
WHITE='\033[1;37m'
NC='\033[0m'

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")

if [ "$EUID" -ne 0 ]; then
  echo "Run as sudo."
  exit 1
fi

get_avail_kb() {
  df -k / | awk 'NR==2 {print $4}'
}

BEFORE_KB=$(get_avail_kb)

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

ORPHANS=$(pacman -Qtdq 2>/dev/null || true)
if [ -n "$ORPHANS" ]; then
    mapfile -t ORPHAN_ARRAY <<< "$ORPHANS"
    run_with_dots "[1/9] Removing orphan packages" pacman -Rns --noconfirm "${ORPHAN_ARRAY[@]}"
else
    run_with_dots "[1/9] Checking orphan packages" true
fi

run_with_dots "[2/9] Cleaning Pacman cache" bash -c \
  "rm -rf /var/cache/pacman/pkg/download-* /var/cache/pacman/pkg/*.part 2>/dev/null || true; paccache -r -k2; paccache -ruk0"

if command -v yay &> /dev/null; then
    run_with_dots "[3/9] Cleaning yay cache ($REAL_USER)" runuser -u "$REAL_USER" -- yay -Sc --aur --noconfirm
elif command -v paru &> /dev/null; then
    run_with_dots "[3/9] Cleaning paru cache ($REAL_USER)" runuser -u "$REAL_USER" -- paru -Sc --aur --noconfirm
else
    run_with_dots "[3/9] Checking for AUR helpers" true
fi

run_with_dots "[4/9] Vacuuming systemd logs older than 2 weeks" journalctl --vacuum-time=2w

run_with_dots "[5/9] Removing systemd coredumps" bash -c "rm -rf /var/lib/systemd/coredump/* /var/log/journal/*/*.journal~ 2>/dev/null || true"

if command -v flatpak &> /dev/null; then
    run_with_dots "[6/9] Cleaning Flatpak leftovers & unused runtimes" flatpak uninstall --unused --delete-data --noninteractive
elif command -v docker &> /dev/null; then
    run_with_dots "[6/9] Pruning Docker assets" docker system prune -af
else
    run_with_dots "[6/9] Checking Flatpak and Docker assets" true
fi

run_with_dots "[7/9] Cleaning user caches, logs, & app leftovers for $REAL_USER" runuser -u "$REAL_USER" -- bash -c '
USER_CACHE_DIRS=(
    "$HOME/.local/share/Trash"
    "$HOME/.cache/thumbnails"
    "$HOME/.cache/fontconfig"
    "$HOME/.cache/mesa_shader_cache"
    "$HOME/.cache/nvidia"

    "$HOME/.cache/mozilla"
    "$HOME/.cache/google-chrome"
    "$HOME/.cache/chromium"
    "$HOME/.cache/BraveSoftware"
    "$HOME/.cache/Vivaldi"

    "$HOME/.cache/pip"
    "$HOME/.cache/go-build"
    "$HOME/.cache/yarn"
    "$HOME/.npm/_cacache"
    "$HOME/.cargo/registry/cache"
    "$HOME/.cargo/git/db"
    "$HOME/.cache/node-gyp"
    "$HOME/.cache/electron"

    "$HOME/.cache/gapless"
    "$HOME/.cache/g4music"
    "$HOME/.config/gapless"
    "$HOME/.config/g4music"
    "$HOME/.cache/spotify"
    "$HOME/.cache/discord"
    "$HOME/.cache/slack"
    "$HOME/.cache/vlc"
    "$HOME/.cache/wine"
)
for target in "${USER_CACHE_DIRS[@]}"; do
    if [ -d "$target" ]; then
        rm -rf "${target:?}"/* 2>/dev/null || true
    fi
done'

run_with_dots "[8/9] Cleaning build directories & broken symlinks" bash -c \
  "runuser -u $REAL_USER -- rm -rf $USER_HOME/.cache/yay/* $USER_HOME/.cache/paru/clone/* 2>/dev/null || true; find /var /tmp -type l ! -exec test -e {} \; -delete 2>/dev/null || true"

if command -v pacdiff &> /dev/null; then
    PACFILES=$(PACMAN_OUTPUT=1 pacdiff -l 2>/dev/null || true)
    run_with_dots "[9/9] Checking for unmerged configuration files (.pacnew / .pacsave)" true
    if [ -n "$PACFILES" ]; then
        echo -e "${YELLOW}WARNING: Unmerged configuration files detected:${NC}"
        echo "$PACFILES"
        echo "Run 'pacdiff' manually after this script finishes to merge them."
    fi
else
    run_with_dots "[9/9] Checking for pacdiff utility" true
fi

AFTER_KB=$(get_avail_kb)
FREED_KB=$((AFTER_KB - BEFORE_KB))

if [ "$FREED_KB" -gt 0 ]; then
    FREED_HUMAN=$(numfmt --to=iec-i --suffix=B $((FREED_KB * 1024)))
else
    FREED_HUMAN="0B"
fi

echo -e "${YELLOW}Total space reclaimed: ${GREEN}${FREED_HUMAN}${NC}"

echo -e "\n${CYAN}Arch Clean Complete${NC}"
