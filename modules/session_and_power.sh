#!/usr/bin/env bash
# Module: session_and_power — xscreensaver LockCommand, session save, screensaver disable, power manager.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_session_and_power() {
  log_info "Configuring session_and_power..."

  xfconf_set "xfce4-session" "/general/LockCommand" "string" "xscreensaver-command -lock"
  xfconf_set "xfce4-session" "/general/SessionName" "string" "Default"
  xfconf_set "xfce4-session" "/general/SaveOnExit" "bool" "true"
  xfconf_set "xfce4-session" "/general/AutoSave" "bool" "true"
  xfconf_set "xfce4-session" "/shutdown/LockScreen" "bool" "false"

  xfconf_set "xfce4-screensaver" "/saver/mode" "int" "0"
  xfconf_set "xfce4-screensaver" "/saver/enabled" "bool" "false"
  xfconf_set "xfce4-screensaver" "/lock/enabled" "bool" "false"
  xfconf_set "xfce4-screensaver" "/lock/saver-activation/enabled" "bool" "false"

  xfconf_set "xfce4-power-manager" "/xfce4-power-manager/show-tray-icon" "bool" "false"
  xfconf_set "xfce4-power-manager" "/xfce4-power-manager/brightness-switch-restore-on-exit" "int" "1"
  xfconf_set "xfce4-power-manager" "/xfce4-power-manager/brightness-switch" "int" "0"
  xfconf_set "xfce4-power-manager" "/xfce4-power-manager/lock-screen-suspend-hibernate" "bool" "false"
  xfconf_set "xfce4-power-manager" "/xfce4-power-manager/logind-handle-lid-switch" "bool" "false"
  xfconf_set "xfce4-power-manager" "/xfce4-power-manager/handle-brightness-keys" "bool" "true"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_session_and_power
fi
