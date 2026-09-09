# reMarkable as a terminal screen

Turn a reMarkable tablet into the display for your Mac's terminal, the way
the Kindle-terminal setup does: you keep typing on the Mac's keyboard, the
shell shows up on the e-ink screen, and the backlit monitor can go dark. It
also works the other way round with a Type Folio, typing on the tablet.

```
   Mac                                            reMarkable
   ┌───────────────────────────┐   USB-C or Wi-Fi  ┌──────────────────────┐
   │  tmux session "eink"      │◄──── ssh ─────────│ yaft (terminal app)  │
   │    ▲                      │                   │   runs mac-terminal  │
   │    │ eink  (your keyboard)│                   │   inside AppLoad     │
   └───────────────────────────┘                   └──────────────────────┘
```

Both ends attach to one tmux session on the Mac. Whatever you type in the
Mac window is drawn on the tablet, and the tablet's size drives the layout
so nothing scrolls off the e-ink screen.

## What this uses

| Piece | Role | Source |
|---|---|---|
| Vellum | package manager for reMarkable 1, 2, Paper Pro and Move | https://github.com/vellum-dev/vellum-cli |
| yaft | framebuffer terminal that runs inside the stock reMarkable UI | https://github.com/timower/rM2-stuff/tree/master/apps/yaft |
| AppLoad + XOVI | app launcher inside the reMarkable UI (pulled in by yaft) | https://github.com/asivery/rm-appload |
| tmux | the shared session on the Mac | Homebrew |

Toltec, the older package manager, only supports reMarkable OS up to 3.3
and does not support the Paper Pro, so this uses Vellum.

## Before you start

- A reMarkable 1, 2, Paper Pro or Paper Pro Move on an OS version Vellum
  covers. Vellum publishes builds per OS version; `vellum add yaft` will
  say so if yours is not covered yet. Check https://vellum.delivery.
- A Mac with Homebrew. The scripts use the bash that ships with macOS.
- The USB-C cable. Over the cable the tablet is `10.11.99.1` and the Mac is
  `10.11.99.2`, with Wi-Fi off on both sides if you like. Wi-Fi works too.
- The tablet's root password. Settings > Help > Copyright and licenses
  (Settings > About on OS 3.9 to 3.18), under "GPLv3 Compliance".
- Paper Pro and Move only: Developer Mode must be on first. Turning it on
  factory-resets the tablet, so sync your notes before you do.
  https://support.remarkable.com/s/article/Developer-mode

Things worth knowing:

- Vellum modifies the tablet's root partition. reMarkable OS updates have
  broken third-party setups before, so turn off automatic updates
  (Settings > General > Software) and run `vellum check-os <version>` before
  you accept one. After an update, `vellum reenable` restores things.
- SSH from the tablet into your Mac is key-based, and the private key lives
  on the tablet. Anyone with root on the tablet can log into your Mac
  account. Keep the tablet's root password to yourself.
- The Mac's Remote Login is turned on for your user only.

## Install

```sh
git clone https://github.com/RockRoque/RockRoque.git
cd RockRoque/remarkable-terminal

./setup-mac.sh          # tmux, Remote Login, config, `eink` command
./setup-remarkable.sh   # tablet plugged in over USB; asks for its root password once
```

`setup-remarkable.sh` does, over SSH to the tablet:

1. Reports the model and OS version.
2. Downloads Vellum's bootstrap script on the Mac, checks it against the
   sha256 published in the vellum-cli README, and runs it on the tablet
   (skipped if Vellum is already there).
3. `vellum add yaft`, which also pulls the AppLoad launcher.
4. Installs `device/mac-terminal.sh` as `/home/root/.local/bin/mac-terminal`
   and writes `/home/root/.config/mac-terminal.conf` with your Mac user,
   the addresses to try (USB first, then your Wi-Fi IP) and the session name.
5. Creates an SSH key on the tablet with dropbear and adds it to
   `~/.ssh/authorized_keys` on the Mac.
6. Registers a "Mac Terminal" entry in AppLoad: a copy of yaft's own app
   manifest pointed at the launcher script.
7. Restarts the tablet UI and test-connects from the tablet to the Mac.

Every step is idempotent, so re-run it after changing anything. Overrides:

```sh
RM_HOST=192.168.1.42 ./setup-remarkable.sh        # tablet over Wi-Fi
MAC_HOSTS="10.11.99.2 192.168.1.10" ./setup-remarkable.sh
MAC_USER=rock SESSION=work ./setup-remarkable.sh
SKIP_RESTART=1 ./setup-remarkable.sh
```

## Daily use

1. On the Mac, open a terminal and run `eink`. That attaches your window to
   the shared tmux session and creates it if needed.
2. On the tablet, open the AppLoad menu from the home screen and tap
   **Mac Terminal**. It connects over USB first, then Wi-Fi, and attaches to
   the same session.
3. Type on the Mac. Turn the monitor off, or `eink` from a tiny window in
   the corner.

Useful bits:

- `eink status` lists the attached clients, so you can confirm the tablet
  is on. `eink kill` ends the session.
- The tablet reconnects by itself every five seconds if the Mac sleeps or
  the cable is pulled. Swipe down from the top edge to leave the app.
- With the Type Folio attached, yaft rotates to landscape and you can type
  on the tablet directly. Without it, the on-screen keyboard shows; long
  press Escape to tuck it away.
- tmux prefix is the default `Ctrl-b`. `Ctrl-b d` detaches the Mac window
  without ending the session.

## Tuning for e-ink

- **Ghosting.** `/home/root/.config/yaft/config.toml` has `auto-refresh`,
  the number of screen updates between full refreshes. The installed
  config uses 256; lower it if text smears, raise it if flashing annoys you.
- **Sleep.** The tablet gets no touch input while you type on the Mac, so
  set Settings > Battery > Auto sleep to the longest option.
- **Colours.** The tmux status bar is black on white. Shell prompts and
  editors that rely on colour look best in a plain or high-contrast theme.
  In micro or vim, pick a monochrome colourscheme.
- **Rotation.** `rotation = "none"` in the yaft config keeps portrait for a
  stand-mounted tablet; `auto-rotate` still flips to landscape with the
  Type Folio.

## Troubleshooting

- **"could not SSH into the tablet"**: plug it in, wake it, and check that
  `ssh root@10.11.99.1` works from the Mac. Over Wi-Fi on OS 3.20 and
  newer, run `rm-ssh-over-wlan on` on the tablet first.
- **`vellum add yaft` refuses**: your OS version is not covered yet. Check
  https://vellum.delivery for the OS ranges of the `yaft` and `appload`
  packages and wait or downgrade; do not force it.
- **Mac Terminal missing from AppLoad**: reboot the tablet. If it is still
  missing, check that `/home/root/xovi/exthome/appload/mac-terminal/external.manifest.json`
  exists and that `vellum info appload` reports it installed.
- **App opens but says "no Mac found"**: the tablet cannot reach any
  address in `MAC_HOSTS`. Over USB that is `10.11.99.2`; check
  `ifconfig` on the Mac for a `10.11.99.x` interface while the cable is in.
  Over Wi-Fi, the Mac and tablet must be on the same network.
- **"Permission denied" from the Mac**: Remote Login is off, or your user
  is not in its allowed list (System Settings > General > Sharing > Remote
  Login > Allow access for). Re-run `setup-remarkable.sh` to re-add the key.
- **tmux not found on the Mac**: `attach.sh` looks in the Homebrew
  locations; `brew install tmux` and try again.
- **Wrong size on the tablet**: tmux uses the smallest attached client.
  Detach stale Mac windows with `eink status` then `tmux detach-client -t <tty>`.

## Uninstall

On the tablet, as root:

```sh
rm -rf /home/root/xovi/exthome/appload/mac-terminal /home/root/.local/bin/mac-terminal \
       /home/root/.config/mac-terminal.conf /home/root/.ssh/mac-terminal.key
vellum del yaft            # keep AppLoad/XOVI if other apps use them
vellum self uninstall      # removes Vellum and its root-partition changes
```

On the Mac: delete the `remarkable-mac-terminal` line from
`~/.ssh/authorized_keys`, remove `~/.config/remarkable-terminal` and
`~/.local/bin/eink`, and turn off Remote Login if nothing else uses it.

## Files

```
setup-mac.sh             Mac: tmux, Remote Login, config, eink command
setup-remarkable.sh      Mac: configures the tablet over SSH
mac/tmux-eink.conf       shared tmux config (smallest-client sizing, no bells)
mac/attach.sh            what the tablet runs on the Mac over SSH
mac/eink                 local attach/status/kill helper
device/mac-terminal.sh   runs on the tablet inside yaft; ssh + reconnect loop
device/yaft-config.toml  yaft settings tuned for e-ink text
```
