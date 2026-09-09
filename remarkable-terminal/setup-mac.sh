#!/bin/bash
# Mac side of the reMarkable terminal setup.
#
# What it does:
#   1. makes sure tmux is installed (via Homebrew when available)
#   2. turns on Remote Login (the SSH server) so the tablet can connect
#   3. installs the shared tmux config, the SSH-side attach script, and the
#      local `eink` command into ~/.config/remarkable-terminal and ~/.local/bin
#   4. prints the addresses the tablet can reach this Mac at
#
# Safe to re-run. Works with the bash 3.2 that ships with macOS.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
CONF="$HOME/.config/remarkable-terminal"
BIN="$HOME/.local/bin"

say()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is meant to run on the Mac, not on the tablet or Linux." >&2
  exit 1
fi

# ---------------------------------------------------------------- 1. tmux
say "Checking tmux"
if command -v tmux >/dev/null 2>&1; then
  note "found $(tmux -V)"
elif command -v brew >/dev/null 2>&1; then
  note "installing tmux with Homebrew"
  brew install tmux
else
  echo "tmux is missing and Homebrew is not installed." >&2
  echo "Install Homebrew (https://brew.sh) and re-run, or install tmux another way." >&2
  exit 1
fi

# --------------------------------------------------------- 2. Remote Login
say "Checking Remote Login (SSH server)"
if sudo -n true 2>/dev/null || [ -t 0 ]; then
  state="$(sudo systemsetup -getremotelogin 2>/dev/null || true)"
  case "$state" in
    *On*)
      note "Remote Login is already on"
      ;;
    *)
      note "turning Remote Login on (needs your password)"
      if sudo systemsetup -setremotelogin on 2>/dev/null; then
        note "Remote Login is on"
      else
        note "could not enable it from the command line."
        note "Turn it on in System Settings > General > Sharing > Remote Login,"
        note "then re-run this script."
      fi
      ;;
  esac
else
  note "no terminal for sudo; enable Remote Login in System Settings > General > Sharing"
fi

# ------------------------------------------------------- 3. install files
say "Installing config and helpers"
mkdir -p "$CONF" "$BIN"
install -m 0644 "$HERE/mac/tmux-eink.conf" "$CONF/tmux-eink.conf"
install -m 0755 "$HERE/mac/attach.sh"      "$CONF/attach.sh"
install -m 0755 "$HERE/mac/eink"           "$BIN/eink"
note "$CONF/tmux-eink.conf"
note "$CONF/attach.sh"
note "$BIN/eink"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    note ""
    note "$BIN is not on your PATH. Add this line to ~/.zshrc:"
    note "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

# ------------------------------------------------------------ 4. addresses
say "Addresses the tablet can use to reach this Mac"
note "USB cable:  10.11.99.2   (always, when the tablet is plugged into this Mac)"
for ifc in en0 en1 en2; do
  ip="$(ipconfig getifaddr "$ifc" 2>/dev/null || true)"
  [ -n "$ip" ] && note "Wi-Fi/LAN:  $ip   ($ifc)"
done
note "Bonjour:    $(scutil --get LocalHostName 2>/dev/null || hostname -s).local (Mac to Mac only; the tablet needs the IP)"
note "SSH user:   $USER"

say "Done on the Mac. Next: plug the tablet in over USB and run ./setup-remarkable.sh"
