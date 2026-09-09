#!/bin/bash
# Tablet side of the reMarkable terminal setup. Run this ON THE MAC with the
# tablet plugged in over USB (or reachable over Wi-Fi via RM_HOST).
#
# What it does, over SSH to the tablet:
#   1. detects the model and OS version
#   2. installs Vellum (the reMarkable package manager) if it is missing,
#      verifying the bootstrap script against the checksum published in the
#      vellum-cli README
#   3. installs yaft (a framebuffer terminal that runs inside the stock UI)
#   4. installs the "Mac Terminal" launcher script and its config
#   5. creates an SSH key on the tablet and authorises it on this Mac
#   6. registers a "Mac Terminal" entry in the AppLoad app menu
#   7. restarts the tablet UI so the new app shows up, then test-connects
#
# Environment overrides:
#   RM_HOST       tablet address            (default 10.11.99.1, the USB address)
#   MAC_USER      Mac login for the tablet  (default: current user)
#   MAC_HOSTS     addresses the tablet tries, in order
#                 (default: "10.11.99.2 <this Mac's Wi-Fi IP>")
#   SESSION       tmux session name         (default eink)
#   SKIP_RESTART  set to 1 to not restart the tablet UI at the end
#
# Safe to re-run. Needs the tablet's root password once (Settings > Help >
# Copyright and licenses, or Settings > About on some OS versions).
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
RM_HOST="${RM_HOST:-10.11.99.1}"
MAC_USER="${MAC_USER:-$USER}"
SESSION="${SESSION:-eink}"
SKIP_RESTART="${SKIP_RESTART:-0}"

VELLUM_BOOTSTRAP_URL="https://github.com/vellum-dev/vellum-cli/releases/latest/download/bootstrap.sh"
VELLUM_README_URL="https://raw.githubusercontent.com/vellum-dev/vellum-cli/main/README.md"

RM_HOME="/home/root"
RM_BIN="$RM_HOME/.local/bin"
RM_CONF="$RM_HOME/.config/mac-terminal.conf"
RM_KEY="$RM_HOME/.ssh/mac-terminal.key"
RM_APPS="$RM_HOME/xovi/exthome/appload"
RM_VELLUM="$RM_HOME/.vellum/bin/vellum"

say()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

if [ "$(uname -s)" != "Darwin" ]; then
  die "run this on the Mac; it talks to the tablet over SSH"
fi
[ -f "$HOME/.config/remarkable-terminal/attach.sh" ] || die "run ./setup-mac.sh first"

# Default host list: USB first, then this Mac's Wi-Fi address.
if [ -z "${MAC_HOSTS:-}" ]; then
  MAC_HOSTS="10.11.99.2"
  for ifc in en0 en1; do
    ip="$(ipconfig getifaddr "$ifc" 2>/dev/null || true)"
    [ -n "$ip" ] && MAC_HOSTS="$MAC_HOSTS $ip"
  done
fi

# ------------------------------------------------------- ssh plumbing
# One multiplexed connection so the root password is asked once. Files are
# pushed through ssh+cat because dropbear on the tablet has no sftp server.
CTL_DIR="$(mktemp -d /tmp/rm-term.XXXXXX)"
trap 'ssh -o ControlPath="$CTL_DIR/ctl" -O exit "root@$RM_HOST" >/dev/null 2>&1 || true; rm -rf "$CTL_DIR"' EXIT
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$CTL_DIR/ctl" -o ControlPersist=10m
          -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)

# shellcheck disable=SC2029  # remote commands are built on the Mac on purpose
rm_sh()  { ssh "${SSH_OPTS[@]}" "root@$RM_HOST" "$@"; }
rm_tty() { ssh -t "${SSH_OPTS[@]}" "root@$RM_HOST" "$@"; }
rm_put() { # rm_put <local file> <remote path> [mode]
  rm_sh "mkdir -p '$(dirname "$2")' && cat > '$2' && chmod ${3:-0644} '$2'" < "$1"
}

say "Connecting to the tablet at root@$RM_HOST"
note "password: Settings > Help > Copyright and licenses (or Settings > About), under GPLv3 Compliance"
rm_sh 'true' || die "could not SSH into the tablet. Is it plugged in and awake? Try RM_HOST=<wifi ip>."

# ------------------------------------------------------- 1. device info
say "Device"
MODEL="$(rm_sh 'cat /sys/devices/soc0/machine 2>/dev/null || echo unknown')"
OS_VER="$(rm_sh 'sed -n "s/^REMARKABLE_RELEASE_VERSION=//p" /usr/share/remarkable/update.conf 2>/dev/null || echo unknown')"
note "model:  $MODEL"
note "OS:     $OS_VER"
note "Vellum publishes per-OS builds; 'vellum add' below will refuse if this OS is not covered yet."

# ------------------------------------------------------- 2. vellum
say "Vellum package manager"
if rm_sh "test -x $RM_VELLUM"; then
  note "already installed"
else
  note "downloading bootstrap script on the Mac"
  curl -fsSL -o "$CTL_DIR/bootstrap.sh" "$VELLUM_BOOTSTRAP_URL"
  curl -fsSL -o "$CTL_DIR/README.md" "$VELLUM_README_URL"
  EXPECTED="$(sed -n 's/.*echo "\([0-9a-f]\{64\}\)  bootstrap.sh".*/\1/p' "$CTL_DIR/README.md" | head -n1)"
  [ -n "$EXPECTED" ] || die "could not find the bootstrap.sh checksum in the vellum-cli README; install Vellum by hand (see README) and re-run"
  ACTUAL="$(shasum -a 256 "$CTL_DIR/bootstrap.sh" | awk '{print $1}')"
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    die "bootstrap.sh checksum mismatch (expected $EXPECTED, got $ACTUAL). Not installing."
  fi
  note "checksum verified: $ACTUAL"
  rm_put "$CTL_DIR/bootstrap.sh" "$RM_HOME/bootstrap.sh" 0755
  note "running the installer on the tablet (answer its prompts if any)"
  rm_tty "bash $RM_HOME/bootstrap.sh"
  rm_sh "rm -f $RM_HOME/bootstrap.sh"
  rm_sh "test -x $RM_VELLUM" || die "Vellum did not install; check the output above"
fi

# ------------------------------------------------------- 3. yaft
say "Terminal emulator (yaft) and the AppLoad launcher it depends on"
rm_tty "$RM_VELLUM update && $RM_VELLUM add yaft"
YAFT_BIN="$(rm_sh "test -x $RM_APPS/yaft/yaft && echo $RM_APPS/yaft/yaft || find $RM_HOME/xovi $RM_HOME/.vellum -type f -name yaft 2>/dev/null | head -n1")"
[ -n "$YAFT_BIN" ] || die "yaft binary not found after install"
note "yaft: $YAFT_BIN"

# ------------------------------------------------------- 4. launcher script
say "Installing the Mac Terminal launcher on the tablet"
rm_put "$HERE/device/mac-terminal.sh" "$RM_BIN/mac-terminal" 0755
rm_sh "mkdir -p $RM_HOME/.config/yaft; test -f $RM_HOME/.config/yaft/config.toml || cat > $RM_HOME/.config/yaft/config.toml" < "$HERE/device/yaft-config.toml"
rm_sh "cat > $RM_CONF" <<CONF
# written by setup-remarkable.sh on $(date '+%Y-%m-%d')
MAC_USER="$MAC_USER"
MAC_HOSTS="$MAC_HOSTS"
SESSION="$SESSION"
KEY="$RM_KEY"
CONF
note "$RM_BIN/mac-terminal"
note "$RM_CONF  (user=$MAC_USER hosts='$MAC_HOSTS' session=$SESSION)"

# ------------------------------------------------------- 5. ssh key
say "SSH key so the tablet can log into this Mac without a password"
PUBKEY="$(rm_sh "
  mkdir -p $RM_HOME/.ssh && chmod 700 $RM_HOME/.ssh
  if command -v dropbearkey >/dev/null 2>&1; then
    if [ ! -f $RM_KEY ]; then
      dropbearkey -t ed25519 -f $RM_KEY >/dev/null 2>&1 || dropbearkey -t rsa -s 3072 -f $RM_KEY >/dev/null
    fi
    dropbearkey -y -f $RM_KEY | grep '^ssh-'
  elif command -v ssh-keygen >/dev/null 2>&1; then
    [ -f $RM_KEY ] || ssh-keygen -q -t ed25519 -N '' -f $RM_KEY
    cat $RM_KEY.pub
  else
    echo NOKEYTOOL
  fi
" | tail -n1)"
case "$PUBKEY" in
  ssh-*) ;;
  *) die "could not create a key on the tablet (no dropbearkey or ssh-keygen)" ;;
esac
PUBKEY="$(echo "$PUBKEY" | awk '{print $1" "$2}') remarkable-mac-terminal"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
if grep -qF "$(echo "$PUBKEY" | awk '{print $2}')" "$HOME/.ssh/authorized_keys"; then
  note "tablet key already authorised on this Mac"
else
  echo "$PUBKEY" >> "$HOME/.ssh/authorized_keys"
  note "added tablet key to ~/.ssh/authorized_keys"
fi

# ------------------------------------------------------- 6. AppLoad entry
say "Registering 'Mac Terminal' in the AppLoad app menu"
rm_sh "
  set -e
  mkdir -p $RM_APPS/mac-terminal
  SRC=$RM_APPS/yaft/external.manifest.json
  DST=$RM_APPS/mac-terminal/external.manifest.json
  if [ -f \"\$SRC\" ]; then
    # Reuse yaft's own manifest (it carries the right framebuffer shim
    # settings for this device); only rename it and point it at our script.
    sed -e 's#\"name\": *\"[^\"]*\"#\"name\": \"Mac Terminal\"#' \
        -e 's#\"application\": *\"[^\"]*\"#\"application\": \"$YAFT_BIN\", \"args\": [\"$RM_BIN/mac-terminal\"]#' \
        \"\$SRC\" > \"\$DST\"
  fi
  if ! grep -q '\"args\"' \"\$DST\" 2>/dev/null || ! grep -q 'Mac Terminal' \"\$DST\" 2>/dev/null; then
    cat > \"\$DST\" <<'JSON'
{
  \"name\": \"Mac Terminal\",
  \"application\": \"$YAFT_BIN\",
  \"args\": [\"$RM_BIN/mac-terminal\"],
  \"aspectRatio\": \"original\",
  \"qtfb\": true,
  \"environment\": {
    \"LD_PRELOAD\": \"/home/root/shims/qtfb-shim.so\",
    \"QTFB_SHIM_MODEL\": \"RM1\",
    \"QTFB_SHIM_RESPECT_APP_REFRESH_MODES\": \"false\",
    \"QTFB_SHIM_RESPECT_FULL_REFRESH_REQUESTS\": \"false\",
    \"QTFB_SHIM_INPUT_PATH_NULL\": \"/dev/input/touchscreen0\",
    \"QTFB_SHIM_INITIAL_DISPLAY_MODE\": \"ANIMATE\"
  }
}
JSON
  fi
  [ -f $RM_APPS/yaft/icon.png ] && cp $RM_APPS/yaft/icon.png $RM_APPS/mac-terminal/icon.png || true
"
note "$RM_APPS/mac-terminal/external.manifest.json"

# ------------------------------------------------------- 7. restart + test
if [ "$SKIP_RESTART" != "1" ]; then
  say "Restarting the tablet UI so AppLoad picks up the new app"
  rm_sh 'systemctl restart xochitl' || note "restart failed; reboot the tablet instead"
fi

say "Test: can the tablet log into this Mac?"
TEST_OK=0
for host in $MAC_HOSTS; do
  if rm_sh "if command -v dbclient >/dev/null 2>&1; then dbclient -y -i $RM_KEY $MAC_USER@$host 'echo ok'; else ssh -i $RM_KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 $MAC_USER@$host 'echo ok'; fi" 2>/dev/null | grep -q '^ok$'; then
    note "$host: ok"; TEST_OK=1; break
  else
    note "$host: no"
  fi
done
if [ "$TEST_OK" = 1 ]; then
  say "All set."
else
  say "Setup finished, but the tablet could not log in yet."
  note "Check that Remote Login is on (System Settings > General > Sharing) and"
  note "that macOS allows your user under Remote Login > 'Allow access for'."
fi
note "On the Mac:     eink              (your keyboard drives the shared session)"
note "On the tablet:  open the AppLoad menu and tap 'Mac Terminal'"
note "Re-run this script any time; it only changes what is missing."
