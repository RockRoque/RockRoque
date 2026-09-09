#!/bin/sh
# Runs ON the reMarkable, inside the yaft terminal, when you open the
# "Mac Terminal" app. It SSHes into the Mac and attaches to the shared tmux
# session. Everything typed on the Mac keyboard (or on the Type Folio) shows
# up here.
#
# Config lives in /home/root/.config/mac-terminal.conf and is written by
# setup-remarkable.sh. Keys:
#   MAC_USER    Mac login name
#   MAC_HOSTS   space-separated addresses to try in order (USB first)
#   SESSION     tmux session name (default: eink)
#   KEY         private key file on the tablet
#
# Busybox sh only: no bash-isms in here.

HOME="${HOME:-/home/root}"; export HOME
CONF="$HOME/.config/mac-terminal.conf"
SESSION="eink"
MAC_HOSTS="10.11.99.2"
KEY="$HOME/.ssh/mac-terminal.key"

if [ -r "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
fi

# The Mac does not know yaft's terminfo entry. xterm-256color is close
# enough and exists everywhere.
TERM=xterm-256color; export TERM

# shellcheck disable=SC2088  # the tilde is expanded by the Mac's login shell, not here
REMOTE_CMD="~/.config/remarkable-terminal/attach.sh"

banner() {
  clear 2>/dev/null
  echo "  reMarkable -> Mac terminal"
  echo "  ------------------------------"
  echo "  user:    $MAC_USER"
  echo "  hosts:   $MAC_HOSTS"
  echo "  session: $SESSION"
  echo
}

# Cheap reachability probe so an unplugged USB link or a stale Wi-Fi address
# fails fast instead of waiting on a TCP timeout. Busybox nc only has -z
# (zero-I/O scan) in some builds, so check the usage text first and skip
# the probe when it is missing.
if nc 2>&1 | grep -q -- '-z'; then
  reachable() { timeout 4 nc -z -w 2 "$1" 22 >/dev/null 2>&1; }
else
  reachable() { return 0; }
fi

connect() {
  host="$1"
  if command -v dbclient >/dev/null 2>&1; then
    # Stock reMarkable OS ships dropbear. -y accepts the Mac's host key on
    # first use, -t asks for a pty (tmux needs one), -i uses our key.
    dbclient -y -t -i "$KEY" "$MAC_USER@$host" "EINK_SESSION=$SESSION $REMOTE_CMD"
  elif command -v ssh >/dev/null 2>&1; then
    ssh -t -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
      "$MAC_USER@$host" "EINK_SESSION=$SESSION $REMOTE_CMD"
  else
    echo "no ssh client found on the tablet (expected dbclient or ssh)" >&2
    return 127
  fi
}

if [ -z "${MAC_USER:-}" ]; then
  banner
  echo "  MAC_USER is not set. Re-run setup-remarkable.sh from the Mac."
  echo "  (Config file: $CONF)"
  sleep 30
  exit 1
fi

attempt=0
while :; do
  attempt=$((attempt + 1))
  banner
  connected=0
  for host in $MAC_HOSTS; do
    if reachable "$host"; then
      echo "  connecting to $host ..."
      connect "$host"
      connected=1
      break
    else
      echo "  $host not reachable"
    fi
  done

  echo
  if [ "$connected" = 1 ]; then
    echo "  session ended. reconnecting in 5s  (swipe down from the top edge to quit)"
  else
    echo "  no Mac found (attempt $attempt). Is it plugged in / on the same Wi-Fi?"
    echo "  retrying in 5s  (swipe down from the top edge to quit)"
  fi
  sleep 5
done
