#!/usr/bin/env bash
# Sandboxed automated test suite for provision-xubuntu.
# Runs all tests against temporary HOME / XDG_* directories with DISPLAY unset
# so the live XFCE desktop session is never modified.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROVISION_IGNORE_REPO_LOCAL=1
PASS_COUNT=0
FAIL_COUNT=0

_TEST_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "${_TEST_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT

pass() {
  (( PASS_COUNT += 1 ))
  printf '  [PASS] %s\n' "$1"
}

fail() {
  (( FAIL_COUNT += 1 ))
  printf '  [FAIL] %s\n' "$1" >&2
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected='$expected', actual='$actual')"
  fi
}

assert_file() {
  local path="$1" label="$2"
  if [[ -f "$path" ]]; then
    pass "$label"
  else
    fail "$label (missing file: $path)"
  fi
}

assert_contains() {
  local path="$1" pattern="$2" label="$3"
  if [[ -f "$path" ]] && grep -Fq -- "$pattern" "$path"; then
    pass "$label"
  else
    fail "$label (pattern '$pattern' not found in $path)"
  fi
}

echo "=== 1. Syntax checks (bash -n) ==="
syntax_ok=1
while IFS= read -r -d '' sh_file; do
  if ! bash -n "$sh_file"; then
    syntax_ok=0
    fail "bash -n $sh_file"
  fi
done < <(find "$REPO_DIR" -maxdepth 2 -type f -name '*.sh' -print0)
if (( syntax_ok )); then
  pass "All .sh scripts pass bash -n"
fi

echo "=== 2. Dry-run checks (zero filesystem side effects) ==="
DRY_HOME="${_TEST_ROOT}/dry_home"
mkdir -p "$DRY_HOME"
for script_cmd in \
  "${REPO_DIR}/provision-xfce.sh --dry-run" \
  "${REPO_DIR}/install-deps.sh --dry-run" \
  "${REPO_DIR}/configure-xfce.sh --dry-run" \
  "${REPO_DIR}/configure-xfce.sh --dry-run --only xfwm4,shortcuts"
do
  if env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
       HOME="$DRY_HOME" XDG_CONFIG_HOME="${DRY_HOME}/.config" XDG_DATA_HOME="${DRY_HOME}/.local/share" \
       bash -c "$script_cmd" >/dev/null 2>&1; then
    pass "dry-run exits 0: ${script_cmd##*/}"
  else
    fail "dry-run failed: ${script_cmd}"
  fi
done
dry_leftovers="$(find "$DRY_HOME" -mindepth 1 | wc -l)"
assert_eq "$dry_leftovers" "0" "dry-run leaves temp HOME completely empty"

dry_deps_out="$(env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
  HOME="$DRY_HOME" XDG_CONFIG_HOME="${DRY_HOME}/.config" XDG_DATA_HOME="${DRY_HOME}/.local/share" \
  "${REPO_DIR}/install-deps.sh" --dry-run 2>&1)"
if [[ "$dry_deps_out" == *"air_gradient_alarm_daemon"* ]]; then
  pass "install-deps.sh --dry-run mentions air_gradient_alarm_daemon"
else
  fail "install-deps.sh --dry-run missing air_gradient_alarm_daemon"
fi

echo "=== 3. Sandboxed end-to-end configure-xfce.sh (--offline + auto dbus-run-session) ==="
E2E_HOME="${_TEST_ROOT}/e2e_home"
E2E_CFG="${E2E_HOME}/.config"
E2E_DATA="${E2E_HOME}/.local/share"
MOCK_BIN="${_TEST_ROOT}/mock_bin"
mkdir -p "${E2E_CFG}/gtk-3.0" "${E2E_CFG}/autostart" "${E2E_HOME}/projects/x-window-shortcuts" "$MOCK_BIN"

# Mock kitty & x-window-move so PATH/exec guards are exercised without host side effects.
printf '#!/bin/sh\nexit 0\n' > "${MOCK_BIN}/kitty"
chmod +x "${MOCK_BIN}/kitty"
printf '#!/bin/sh\nexit 0\n' > "${E2E_HOME}/projects/x-window-shortcuts/x-window-move"
chmod +x "${E2E_HOME}/projects/x-window-shortcuts/x-window-move"

# Pre-seed existing gtk-3.0 key and legacy Compton autostart to verify preservation & migration.
cat > "${E2E_CFG}/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=0
gtk-cursor-theme-size=24
EOF

cat > "${E2E_CFG}/autostart/Compton Compositor.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Compton Compositor
Exec=/usr/bin/compton
Hidden=false
EOF

if env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
     PATH="${MOCK_BIN}:${PATH}" \
     HOME="$E2E_HOME" XDG_CONFIG_HOME="$E2E_CFG" XDG_DATA_HOME="$E2E_DATA" \
     PROVISION_NO_RELOAD=1 \
     "${REPO_DIR}/configure-xfce.sh" --offline --redshift-location 40.7128:-74.0060; then
  pass "configure-xfce.sh --offline exited 0 cleanly via auto dbus-run-session"
else
  fail "configure-xfce.sh --offline failed"
fi

echo "=== 4. xfconf-query property assertions in isolated dbus-run-session ==="
xfconf_check_out="$(
  env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    HOME="$E2E_HOME" XDG_CONFIG_HOME="$E2E_CFG" XDG_DATA_HOME="$E2E_DATA" \
    dbus-run-session -- bash -c '
      set -u
      q() { xfconf-query -c "$1" -p "$2" 2>/dev/null || echo "__MISSING__"; }
      echo "xfwm4_theme=$(q xfwm4 /general/theme)"
      echo "xfwm4_borderless_max=$(q xfwm4 /general/borderless_maximize)"
      echo "xfwm4_titleless_max=$(q xfwm4 /general/titleless_maximize)"
      echo "xfwm4_easy_click=$(q xfwm4 /general/easy_click)"
      echo "xfwm4_compositing=$(q xfwm4 /general/use_compositing)"
      echo "xfwm4_ws_count=$(q xfwm4 /general/workspace_count)"
      echo "xfwm4_shadow_y=$(q xfwm4 /general/shadow_delta_y)"
      echo "xfwm4_ws_names_count=$(xfconf-query -c xfwm4 -p /general/workspace_names 2>/dev/null | grep -c "^Workspace ")"
      echo "xset_theme=$(q xsettings /Net/ThemeName)"
      echo "xset_icon=$(q xsettings /Net/IconThemeName)"
      echo "xset_font=$(q xsettings /Gtk/FontName)"
      echo "xset_mono=$(q xsettings /Gtk/MonospaceFontName)"
      echo "xset_dpi=$(q xsettings /Xft/DPI)"
      echo "xset_hint=$(q xsettings /Xft/HintStyle)"
      echo "gs_scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo __MISSING__)"
      echo "gs_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo __MISSING__)"
      echo "gs_icon=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo __MISSING__)"
      echo "gs_font=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null || echo __MISSING__)"
      echo "gs_mono=$(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null || echo __MISSING__)"
      echo "sc_super_right=$(q xfce4-keyboard-shortcuts "/commands/custom/<Super>Right")"
      echo "sc_super2_sn=$(q xfce4-keyboard-shortcuts "/commands/custom/<Super>2/startup-notify")"
      echo "sc_super3_sn=$(q xfce4-keyboard-shortcuts "/commands/custom/<Super>3/startup-notify")"
      echo "sc_scroll_up=$(q xfce4-keyboard-shortcuts "/commands/custom/ScrollUp")"
      echo "sc_close=$(q xfce4-keyboard-shortcuts "/xfwm4/custom/<Shift><Alt>dollar")"
      echo "sc_alt_f4=$(q xfce4-keyboard-shortcuts "/xfwm4/custom/<Alt>F4")"
      echo "sc_wm_alt_tab=$(q xfce4-keyboard-shortcuts "/xfwm4/custom/<Alt>Tab")"
      echo "sc_ctrl_alt_tab=$(q xfce4-keyboard-shortcuts "/xfwm4/custom/<Ctrl><Alt>Tab")"
      echo "kb_delay=$(q keyboards /Default/KeyRepeat/Delay)"
      echo "kb_rate=$(q keyboards /Default/KeyRepeat/Rate)"
      echo "kb_numlock=$(q keyboards /Default/Numlock)"
      echo "ptr_accel=$(q pointers /MoErgo_Glove80_Left_Mouse/Acceleration)"
      echo "mousekeys=$(q accessibility /MouseKeys)"
      echo "panel_autohide=$(q xfce4-panel /panels/panel-1/autohide-behavior)"
      echo "panel_size=$(q xfce4-panel /panels/panel-1/size)"
      echo "panel_clock=$(q xfce4-panel /plugins/plugin-12/digital-time-format)"
      echo "panel_clipman=$(q xfce4-panel /plugins/plugin-15)"
      echo "sess_lock=$(q xfce4-session /general/LockCommand)"
      echo "sess_save=$(q xfce4-session /general/SaveOnExit)"
      echo "saver_enabled=$(q xfce4-screensaver /saver/enabled)"
      echo "pwr_lock_susp=$(q xfce4-power-manager /xfce4-power-manager/lock-screen-suspend-hibernate)"
      echo "thunar_view=$(q thunar /last-view)"
      echo "notifyd_log=$(q xfce4-notifyd /log-max-size-enabled)"
    '
)"

declare -A got=()
while IFS='=' read -r k v; do
  [[ -n "$k" ]] && got["$k"]="$v"
done <<< "$xfconf_check_out"

assert_eq "${got[xfwm4_theme]}" "no-titlebar" "xfwm4 theme is no-titlebar"
assert_eq "${got[xfwm4_borderless_max]}" "true" "xfwm4 borderless_maximize=true"
assert_eq "${got[xfwm4_titleless_max]}" "true" "xfwm4 titleless_maximize=true"
assert_eq "${got[xfwm4_easy_click]}" "None" "xfwm4 easy_click=None"
assert_eq "${got[xfwm4_compositing]}" "false" "xfwm4 use_compositing=false"
assert_eq "${got[xfwm4_ws_count]}" "5" "xfwm4 workspace_count=5"
assert_eq "${got[xfwm4_shadow_y]}" "-3" "xfwm4 shadow_delta_y=-3 (negative int)"
assert_eq "${got[xfwm4_ws_names_count]}" "5" "xfwm4 workspace_names has 5 entries"
assert_eq "${got[xset_theme]}" "Kanagawa-BL" "xsettings theme=Kanagawa-BL"
assert_eq "${got[xset_icon]}" "elementary-xfce" "xsettings icon=elementary-xfce"
assert_eq "${got[xset_font]}" "Inter Display 12" "xsettings font=Inter Display 12"
assert_eq "${got[xset_mono]}" "Azeret Mono 10" "xsettings mono=Azeret Mono 10"
assert_eq "${got[xset_dpi]}" "-1" "xsettings Xft/DPI=-1 (negative int)"
assert_eq "${got[xset_hint]}" "hintfull" "xsettings HintStyle=hintfull"
assert_eq "${got[gs_scheme]}" "'prefer-dark'" "gsettings color-scheme=prefer-dark"
assert_eq "${got[gs_theme]}" "'Kanagawa-BL'" "gsettings gtk-theme=Kanagawa-BL"
assert_eq "${got[gs_icon]}" "'elementary-xfce'" "gsettings icon-theme=elementary-xfce"
assert_eq "${got[gs_font]}" "'Inter Display 12'" "gsettings font-name=Inter Display 12"
assert_eq "${got[gs_mono]}" "'Azeret Mono 10'" "gsettings monospace-font-name=Azeret Mono 10"
assert_eq "${got[sc_super_right]}" "${E2E_HOME}/projects/x-window-shortcuts/x-window-move right" "shortcut <Super>Right uses dynamic \$HOME"
assert_eq "${got[sc_super2_sn]}" "true" "shortcut <Super>2/startup-notify=true"
assert_eq "${got[sc_super3_sn]}" "true" "shortcut <Super>3/startup-notify=true"
assert_eq "${got[sc_scroll_up]}" "/usr/bin/xdotool click 4" "shortcut ScrollUp bound"
assert_eq "${got[sc_close]}" "close_window_key" "shortcut <Shift><Alt>dollar=close_window_key"
assert_eq "${got[sc_alt_f4]}" "__MISSING__" "shortcut <Alt>F4 intentionally unbound"
assert_eq "${got[sc_wm_alt_tab]}" "__MISSING__" "xfwm4 <Alt>Tab intentionally unbound"
assert_eq "${got[sc_ctrl_alt_tab]}" "null" "xfwm4 <Ctrl><Alt>Tab=null"
assert_eq "${got[kb_delay]}" "250" "keyboards Delay=250"
assert_eq "${got[kb_rate]}" "100" "keyboards Rate=100"
assert_eq "${got[kb_numlock]}" "true" "keyboards Numlock=true"
assert_eq "${got[mousekeys]}" "__MISSING__" "accessibility MouseKeys omitted"
assert_eq "${got[panel_autohide]}" "1" "panel autohide-behavior=1"
assert_eq "${got[panel_size]}" "26" "panel size=26"
assert_eq "${got[panel_clock]}" "%a %b %_d, %R" "panel clock format matches"
assert_eq "${got[panel_clipman]}" "xfce4-clipman-plugin" "panel clipman plugin present"
assert_eq "${got[sess_lock]}" "xscreensaver-command -lock" "xfce4-session LockCommand"
assert_eq "${got[sess_save]}" "true" "xfce4-session SaveOnExit=true"
assert_eq "${got[saver_enabled]}" "false" "xfce4-screensaver disabled"
assert_eq "${got[pwr_lock_susp]}" "false" "power-manager lock-screen-suspend-hibernate=false"
assert_eq "${got[thunar_view]}" "ThunarDetailsView" "thunar last-view=ThunarDetailsView"
assert_eq "${got[notifyd_log]}" "true" "xfce4-notifyd log-max-size-enabled=true"

if [[ "${got[ptr_accel]}" == 10* ]]; then
  pass "pointers Glove80 Acceleration=10 (${got[ptr_accel]})"
else
  fail "pointers Glove80 Acceleration unexpected: '${got[ptr_accel]}'"
fi

echo "=== 5. Persisted XML, theme, font, GTK & autostart file assertions ==="
PANEL_XML="${E2E_CFG}/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
assert_file "$PANEL_XML" "xfce4-panel.xml flushed to disk on dbus exit"
assert_contains "$PANEL_XML" '<property name="panels" type="array">' "xfce4-panel /panels saved as array (via -a)"
assert_contains "$PANEL_XML" '<value type="int" value="1"/>' "xfce4-panel /panels contains panel id 1"
if grep -qE 'known-items|mpris-players' "$PANEL_XML"; then
  fail "xfce4-panel.xml contains stale known-items/mpris-players"
else
  pass "xfce4-panel.xml has zero stale runtime cruft"
fi

THEMERC="${E2E_HOME}/.themes/no-titlebar/xfwm4/themerc"
assert_file "$THEMERC" "no-titlebar themerc created"
assert_eq "$(wc -c < "$THEMERC")" "0" "no-titlebar themerc is 0 bytes"
assert_file "${E2E_HOME}/.themes/Kanagawa-BL/index.theme" "Kanagawa-BL snapshot installed"
font_count="$(find "${E2E_DATA}/fonts/AzeretMono" -maxdepth 1 -type f -name 'AzeretMono-*.ttf' | wc -l)"
assert_eq "$font_count" "18" "18 static AzeretMono TTFs installed"

assert_contains "${E2E_CFG}/gtk-3.0/settings.ini" "gtk-application-prefer-dark-theme=1" "gtk-3.0 dark theme updated to 1"
assert_contains "${E2E_CFG}/gtk-3.0/settings.ini" "gtk-cursor-theme-size=24" "gtk-3.0 preserved unrelated existing key"
assert_contains "${E2E_CFG}/gtk-4.0/settings.ini" "gtk-application-prefer-dark-theme=1" "gtk-4.0 dark theme set to 1"

assert_contains "${E2E_CFG}/autostart/Picom Compositor.desktop" "Exec=/usr/bin/picom --backend glx --vsync" "Picom autostart created"
assert_contains "${E2E_CFG}/autostart/Compton Compositor.desktop" "Hidden=true" "Legacy Compton autostart disabled cleanly"
assert_contains "${E2E_CFG}/autostart/Rofi Window Watcher Daemon.desktop" "Exec=${E2E_HOME}/projects/x-window-shortcuts/window-watcher-daemon.sh" "Rofi watcher uses dynamic \$HOME"
assert_contains "${E2E_CFG}/autostart/redshift-gtk.desktop" "Exec=/usr/bin/redshift -l 40.7128:-74.0060" "Redshift uses custom --redshift-location"
for hidden_f in xfce4-screensaver.desktop light-locker.desktop geoclue-demo-agent.desktop org.gnome.DejaDup.Monitor.desktop org.gnome.Evolution-alarm-notify.desktop; do
  assert_contains "${E2E_CFG}/autostart/${hidden_f}" "Hidden=true" "Autostart hidden: ${hidden_f}"
done

assert_contains "${E2E_CFG}/xfce4/helpers.rc" "WebBrowser=google-chrome" "helpers.rc WebBrowser=google-chrome"
assert_contains "${E2E_CFG}/xfce4/helpers.rc" "TerminalEmulator=kitty" "helpers.rc TerminalEmulator=kitty when kitty on PATH"
assert_contains "${E2E_CFG}/xfce4/xfce4-screenshooter" "region=3" "screenshooter region=3"
assert_contains "${E2E_CFG}/xfce4/xfce4-screenshooter" "screenshot_dir=file:${E2E_HOME}/Pictures" "screenshooter dir uses dynamic \$HOME"

AG_UNIT="${E2E_CFG}/systemd/user/airgradient-monitor.service"
AG_CFG="${E2E_CFG}/airgradient-monitor/config.json"
assert_file "$AG_UNIT" "airgradient-monitor.service installed"
assert_contains "$AG_UNIT" "Type=notify" "airgradient unit uses Type=notify"
assert_contains "$AG_UNIT" "ExecStart=%h/.local/bin/airgradient-monitor -config %h/.config/airgradient-monitor/config.json" "airgradient unit ExecStart matches ~/.local/bin binary"
assert_contains "$AG_UNIT" "RestartPreventExitStatus=2" "airgradient unit sets RestartPreventExitStatus=2"
assert_file "$AG_CFG" "airgradient config.json seeded"
assert_eq "$(stat -c '%a' "$AG_CFG")" "600" "airgradient config.json has mode 600"
if python3 -m json.tool "$AG_CFG" >/dev/null 2>&1; then
  pass "airgradient config.json is valid JSON"
else
  fail "airgradient config.json is invalid JSON"
fi
assert_contains "$AG_CFG" '"desktop": { "enabled": true' "airgradient config enables native Linux desktop notifications"
assert_contains "$AG_CFG" '"paplay"' "airgradient config uses paplay for critical bell"
assert_contains "$AG_CFG" '/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga' "airgradient config specifies alarm-clock-elapsed.oga"

echo "=== 6. Idempotency + secret preservation + automatic backup check ==="
sed -i 's/YOUR_AIRGRADIENT_API_TOKEN/TEST_REAL_TOKEN_123/' "$AG_CFG"
chmod 600 "$AG_CFG"
if env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
     PATH="${MOCK_BIN}:${PATH}" \
     HOME="$E2E_HOME" XDG_CONFIG_HOME="$E2E_CFG" XDG_DATA_HOME="$E2E_DATA" \
     PROVISION_NO_RELOAD=1 \
     "${REPO_DIR}/configure-xfce.sh" --offline >/dev/null; then
  pass "Second run of configure-xfce.sh --offline succeeded (idempotent)"
else
  fail "Second run of configure-xfce.sh --offline failed"
fi
backup_count="$(find "${E2E_CFG}/xfce4/xfconf/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
if (( backup_count >= 1 )); then
  pass "Automatic timestamped xfconf backup created (count=${backup_count})"
else
  fail "No backup directory found under ${E2E_CFG}/xfce4/xfconf/backups"
fi
assert_contains "$AG_CFG" "TEST_REAL_TOKEN_123" "Second run preserved existing airgradient api_token"

echo "=== 7. install-deps.sh --offline asset fallback + --only / invalid flag checks ==="
DEPS_HOME="${_TEST_ROOT}/deps_home"
mkdir -p "$DEPS_HOME"
if HOME="$DEPS_HOME" XDG_CONFIG_HOME="${DEPS_HOME}/.config" XDG_DATA_HOME="${DEPS_HOME}/.local/share" \
     "${REPO_DIR}/install-deps.sh" --offline --skip-apt --skip-clone --skip-assets >/dev/null; then
  pass "install-deps.sh --offline --skip-apt --skip-clone --skip-assets exited 0"
else
  fail "install-deps.sh --offline --skip-all failed"
fi
if HOME="$DEPS_HOME" XDG_CONFIG_HOME="${DEPS_HOME}/.config" XDG_DATA_HOME="${DEPS_HOME}/.local/share" \
     "${REPO_DIR}/install-deps.sh" --offline --skip-apt --skip-clone >/dev/null; then
  pass "install-deps.sh --offline --skip-apt --skip-clone exited 0"
else
  fail "install-deps.sh --offline fallback failed"
fi
assert_file "${DEPS_HOME}/.themes/Kanagawa-BL/gtk-3.0/gtk.css" "install-deps.sh offline fallback installed Kanagawa-BL"
deps_fonts="$(find "${DEPS_HOME}/.local/share/fonts/AzeretMono" -maxdepth 1 -type f -name 'AzeretMono-*.ttf' | wc -l)"
assert_eq "$deps_fonts" "18" "install-deps.sh offline fallback installed 18 AzeretMono TTFs"

ONLY_HOME="${_TEST_ROOT}/only_home"
mkdir -p "$ONLY_HOME"
env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
  HOME="$ONLY_HOME" XDG_CONFIG_HOME="${ONLY_HOME}/.config" XDG_DATA_HOME="${ONLY_HOME}/.local/share" \
  PROVISION_NO_RELOAD=1 \
  "${REPO_DIR}/provision-xfce.sh" --no-packages --offline --only xfwm4 --no-backup >/dev/null
assert_file "${ONLY_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" "provision-xfce.sh --no-packages --only xfwm4 wrote xfwm4.xml"
if [[ ! -f "${ONLY_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml" ]]; then
  pass "--only xfwm4 skipped other modules (no thunar.xml)"
else
  fail "--only xfwm4 unexpectedly created thunar.xml"
fi

if "${REPO_DIR}/configure-xfce.sh" --only nonexistent_module >/dev/null 2>&1; then
  fail "Invalid module name should have exited non-zero"
else
  pass "Invalid module name cleanly rejected with non-zero exit"
fi

echo "=== 8. REDSHIFT_LOCATION parameterization (unset vs config.local) ==="
RS_HOME="${_TEST_ROOT}/rs_home"
RS_CFG="${RS_HOME}/.config"
mkdir -p "$RS_HOME"
env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u REDSHIFT_LOCATION \
  HOME="$RS_HOME" XDG_CONFIG_HOME="$RS_CFG" XDG_DATA_HOME="${RS_HOME}/.local/share" \
  "${REPO_DIR}/configure-xfce.sh" --only autostart --no-backup >/dev/null 2>&1
assert_file "${RS_CFG}/autostart/Picom Compositor.desktop" "unset REDSHIFT_LOCATION still writes Picom autostart"
if [[ ! -f "${RS_CFG}/autostart/redshift-gtk.desktop" ]]; then
  pass "unset REDSHIFT_LOCATION skips redshift-gtk.desktop cleanly"
else
  fail "unset REDSHIFT_LOCATION should not create redshift-gtk.desktop"
fi

mkdir -p "${RS_CFG}/provision-xubuntu"
cat > "${RS_CFG}/provision-xubuntu/config.local" <<'EOF'
REDSHIFT_LOCATION="51.5074:-0.1278"
EOF
env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u REDSHIFT_LOCATION \
  HOME="$RS_HOME" XDG_CONFIG_HOME="$RS_CFG" XDG_DATA_HOME="${RS_HOME}/.local/share" \
  "${REPO_DIR}/configure-xfce.sh" --only autostart --no-backup >/dev/null 2>&1
assert_contains "${RS_CFG}/autostart/redshift-gtk.desktop" "Exec=/usr/bin/redshift -l 51.5074:-0.1278" "config.local REDSHIFT_LOCATION applied to redshift-gtk.desktop"

echo "========================================"
printf 'Summary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
