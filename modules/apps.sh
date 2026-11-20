#!/usr/bin/env bash
# Module: apps — Thunar defaults, xfce4-notifyd, xfce4-screenshooter, and helpers.rc.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_apps() {
  log_info "Configuring apps..."

  xfconf_set "thunar" "/last-view" "string" "ThunarDetailsView"
  xfconf_set "thunar" "/last-location-bar" "string" "ThunarLocationEntry"
  xfconf_set "thunar" "/last-sort-column" "string" "THUNAR_COLUMN_DATE_MODIFIED"
  xfconf_set "thunar" "/last-sort-order" "string" "GTK_SORT_DESCENDING"
  xfconf_set "thunar" "/misc-single-click" "bool" "false"

  xfconf_set "xfce4-notifyd" "/do-not-disturb" "bool" "false"
  xfconf_set "xfce4-notifyd" "/log-max-size-enabled" "bool" "true"

  local xfce_cfg
  xfce_cfg="$(config_home)/xfce4"

  local ss_file="${xfce_cfg}/xfce4-screenshooter"
  kv_set "$ss_file" "screenshot_dir" "file:${HOME}/Pictures"
  kv_set "$ss_file" "action" "2"
  kv_set "$ss_file" "delay" "0"
  kv_set "$ss_file" "region" "3"
  kv_set "$ss_file" "show_mouse" "1"
  kv_set "$ss_file" "last_extension" "png"
  kv_set "$ss_file" "show_border" "1"
  kv_set "$ss_file" "show_in_folder" "false"

  local helpers_file="${xfce_cfg}/helpers.rc"
  kv_set "$helpers_file" "WebBrowser" "google-chrome"
  if command -v kitty >/dev/null 2>&1 || [[ "${PROVISION_FORCE_KITTY:-0}" == "1" ]]; then
    kv_set "$helpers_file" "TerminalEmulator" "kitty"
  else
    log_info "kitty not found on PATH; leaving TerminalEmulator unset in ${helpers_file}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_apps
fi
