# provision-xubuntu

Idempotent provisioning scripts that configure a fresh Xubuntu / XFCE 4 workstation with borderless windows (`no-titlebar`), dark mode (`Kanagawa-BL`, `elementary-xfce`, GTK3/4 `prefer-dark`), fonts (`Inter Display`, `Azeret Mono`), tiling/navigation keyboard shortcuts (`x-window-shortcuts` + `rofi`), `picom` v12 compositing, `xfce4-panel`, `xscreensaver`, power settings, Redshift, and XFCE app defaults.

## Structure

- `./provision-xfce.sh` — Single entrypoint orchestrating `./install-deps.sh` then `./configure-xfce.sh`.
- `./install-deps.sh` — Installs missing `apt` packages, clones [`marcel-valdez/x-window-shortcuts`](https://github.com/marcel-valdez/x-window-shortcuts) and builds [`marcel-valdez/air_gradient_alarm_daemon`](https://github.com/marcel-valdez/air_gradient_alarm_daemon) into `~/.local/bin/airgradient-monitor`, and installs `Kanagawa-BL` and `Azeret Mono` (download-first from GitHub, automatic fallback to vendored snapshots under `assets/`).
- `./configure-xfce.sh` — Unprivileged `xfconf-query` / `gsettings` / autostart / systemd user unit setup with timestamped XML backup (`~/.config/xfce4/xfconf/backups/`) and automatic `dbus-run-session` fallback for headless runs.
- `modules/` — Independent modules (`themes_and_fonts`, `xfwm4`, `appearance`, `shortcuts`, `input`, `panel`, `session_and_power`, `autostart`, `apps`, `airgradient`).

## Usage

Full setup on a fresh machine:

```bash
./provision-xfce.sh --yes
```

Offline or unprivileged re-configuration (uses vendored `assets/` snapshots, skips `apt` and network):

```bash
./provision-xfce.sh --no-packages --offline
# or directly:
./configure-xfce.sh --offline
```

Preview without making changes:

```bash
./provision-xfce.sh --dry-run
```

Configure local overrides (Redshift coordinates, git-ignored via `*.local`):

```bash
cp config.local.example config.local   # set REDSHIFT_LOCATION="37.7749:-122.4194"
# Or place it at ~/.config/provision-xubuntu/config.local, or export REDSHIFT_LOCATION.
```

Customize Redshift coordinates on the CLI or run selected modules:

```bash
./provision-xfce.sh --only xfwm4,shortcuts --redshift-location 37.7749:-122.4194
./provision-xfce.sh --skip panel,apps
```

## AirGradient Monitor Setup

The `airgradient` module installs `~/.config/systemd/user/airgradient-monitor.service`, seeds `~/.config/airgradient-monitor/config.json` (mode `600`, configured with `paplay` for reliable critical alarms even when GTK event sounds are disabled) if absent, enables the systemd user unit, and automatically installs the Xfce Generic Monitor panel widget when `xfce4-genmon-plugin` is present. On a fresh machine:

1. Edit `~/.config/airgradient-monitor/config.json` and set `"api_token"` (and `"location_id"` if needed).
2. Start the daemon:
   ```bash
   systemctl --user start airgradient-monitor.service
   systemctl --user status airgradient-monitor.service
   ```
3. *(Manual panel refresh/install, if needed)*:
   ```bash
   make -C ~/projects/air_gradient_alarm_daemon install-panel
   ```

## Verification (Isolated Sandbox)

Runs `bash -n`, `--dry-run`, full E2E provisioning inside a throwaway temporary `HOME`/`XDG_CONFIG_HOME` using `dbus-run-session` (zero mutation to your live desktop), backup/idempotency checks, and offline fallback tests:

```bash
bash tests/test_provision.sh
```
