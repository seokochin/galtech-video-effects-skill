#!/usr/bin/env bash
# Free Reel Effects — installer for Mac and Linux
# Created by GALTech School of Technology · www.galtechlearning.com
#
# Checks every requirement, installs what is missing, downloads the free AI model + fonts,
# and confirms the skill is ready to use.
set -u
cd "$(dirname "$0")"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { printf "${GREEN}  ✔ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}  ➜ %s${NC}\n" "$1"; }
fail() { printf "${RED}  ✘ %s${NC}\n" "$1"; }

printf "\n${BOLD}Free Reel Effects — installer${NC}\n"
printf "Created by GALTech School of Technology · www.galtechlearning.com\n\n"

OS="$(uname -s)"
PKG=""
if [ "$OS" = "Darwin" ]; then
  if command -v brew >/dev/null 2>&1; then PKG="brew"; else
    warn "Homebrew not found. Installing Homebrew (needed for ffmpeg)…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && PKG="brew"
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
elif command -v apt-get >/dev/null 2>&1; then PKG="apt"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
fi

install_pkg() {  # $1 = command name, $2 = package name
  case "$PKG" in
    brew)   brew install "$2" ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y "$2" ;;
    dnf)    sudo dnf install -y "$2" ;;
    pacman) sudo pacman -S --noconfirm "$2" ;;
    *)      fail "Please install $1 manually, then run this script again."; exit 1 ;;
  esac
}

printf "${BOLD}1. System tools${NC}\n"
for pair in "python3:python3" "ffmpeg:ffmpeg" "curl:curl"; do
  cmd="${pair%%:*}"; pkg="${pair##*:}"
  [ "$cmd" = "python3" ] && [ "$PKG" = "brew" ] && pkg="python"
  if command -v "$cmd" >/dev/null 2>&1; then ok "$cmd found"
  else warn "$cmd missing — installing…"; install_pkg "$cmd" "$pkg"
       command -v "$cmd" >/dev/null 2>&1 && ok "$cmd installed" || { fail "$cmd could not be installed"; exit 1; }
  fi
done
if [ "$PKG" = "apt" ] && ! python3 -m pip --version >/dev/null 2>&1; then install_pkg pip python3-pip; fi

PYV=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')
python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,9) else 1)' && ok "Python $PYV (3.9+ needed)" || { fail "Python $PYV is too old — install Python 3.9 or newer"; exit 1; }

printf "\n${BOLD}2. Python packages${NC}\n"
PKGS="numpy opencv-python-headless pillow onnxruntime"
if python3 -c "import numpy, cv2, PIL, onnxruntime" >/dev/null 2>&1; then ok "numpy, opencv, pillow, onnxruntime already installed"
else
  warn "Installing $PKGS…"
  python3 -m pip install -q $PKGS 2>/dev/null \
    || python3 -m pip install -q --user $PKGS 2>/dev/null \
    || python3 -m pip install -q --user --break-system-packages $PKGS
  python3 -c "import numpy, cv2, PIL, onnxruntime" >/dev/null 2>&1 && ok "Python packages installed" || { fail "Python packages failed to install"; exit 1; }
fi

printf "\n${BOLD}3. Free AI model + fonts (~180 MB, once)${NC}\n"
python3 free-reel-effects/fx.py setup || { fail "Download failed — check your internet connection"; exit 1; }

printf "\n${BOLD}4. Final check${NC}\n"
python3 - <<'EOF'
import os, numpy, cv2, PIL, onnxruntime
m = os.path.expanduser('~/.free_reel_fx')
need = ['u2net_human_seg.onnx', 'Montserrat.ttf', 'PlayfairDisplay.ttf']
miss = [n for n in need if not os.path.exists(os.path.join(m, n))]
print('  ✔ opencv', cv2.__version__, '· onnxruntime', onnxruntime.__version__, '· numpy', numpy.__version__)
print('  ✘ missing: ' + ', '.join(miss) if miss else '  ✔ model and fonts ready in ' + m)
EOF
printf "\n${GREEN}${BOLD}All set!${NC} Try it:\n"
printf "  python3 free-reel-effects/fx.py all --input my_clip.mp4 --output my_reel.mp4 --title \"My Shop\" --word SALE\n\n"
printf "Free Reel Effects · created by GALTech School of Technology · www.galtechlearning.com\n"
