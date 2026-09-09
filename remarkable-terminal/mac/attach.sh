#!/bin/sh
# Runs on the Mac, invoked by the reMarkable over SSH.
# sshd runs commands through a non-interactive login shell, which does not
# load Homebrew's PATH, so add the usual tmux locations explicitly.
PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:$HOME/.local/bin:$PATH"
export PATH

CONF="$HOME/.config/remarkable-terminal"
SESSION="${EINK_SESSION:-eink}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed on this Mac. Run: brew install tmux" >&2
  exit 1
fi

# -A attaches if the session exists, creates it otherwise. The config file
# only matters the first time the server starts, which is fine.
exec tmux -f "$CONF/tmux-eink.conf" new-session -A -s "$SESSION"
