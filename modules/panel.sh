#!/usr/bin/env bash
# Module: panel — clean single 26px autohiding top panel with 14 plugins (no runtime cruft).

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_panel() {
  log_info "Configuring panel..."

  local ch="xfce4-panel"
  xfconf_reset "$ch" "/panels"
  xfconf_reset "$ch" "/plugins"

  xfconf_set "$ch" "/configver" "int" "2"
  # Force single-element array so panel-1 isn't stored as scalar int.
  xfconf_set_array "$ch" "/panels" "int" "1"

  local -a props=(
    "/panels/panel-1/position|string|p=6;x=0;y=0"
    "/panels/panel-1/length|uint|100"
    "/panels/panel-1/position-locked|bool|true"
    "/panels/panel-1/icon-size|uint|16"
    "/panels/panel-1/size|uint|26"
    "/panels/panel-1/autohide-behavior|uint|1"
    "/panels/panel-1/span-monitors|bool|false"
    "/panels/panel-1/background-style|uint|1"
    "/panels/panel-1/output-name|string|Automatic"

    "/plugins/plugin-1|string|applicationsmenu"
    "/plugins/plugin-2|string|tasklist"
    "/plugins/plugin-2/grouping|uint|1"
    "/plugins/plugin-3|string|separator"
    "/plugins/plugin-3/expand|bool|true"
    "/plugins/plugin-3/style|uint|0"
    "/plugins/plugin-4|string|pager"
    "/plugins/plugin-5|string|separator"
    "/plugins/plugin-5/style|uint|0"
    "/plugins/plugin-6|string|systray"
    "/plugins/plugin-6/show-frame|bool|false"
    "/plugins/plugin-6/square-icons|bool|true"
    "/plugins/plugin-6/icon-size|int|0"
    "/plugins/plugin-6/single-row|bool|true"
    "/plugins/plugin-8|string|pulseaudio"
    "/plugins/plugin-8/enable-keyboard-shortcuts|bool|true"
    "/plugins/plugin-8/show-notifications|bool|true"
    "/plugins/plugin-9|string|power-manager-plugin"
    "/plugins/plugin-10|string|notification-plugin"
    "/plugins/plugin-11|string|separator"
    "/plugins/plugin-11/style|uint|0"
    "/plugins/plugin-12|string|clock"
    "/plugins/plugin-12/mode|uint|2"
    "/plugins/plugin-12/digital-layout|uint|3"
    "/plugins/plugin-12/digital-format|string|%a %b %_d, %R"
    "/plugins/plugin-12/digital-time-format|string|%a %b %_d, %R"
    "/plugins/plugin-13|string|separator"
    "/plugins/plugin-13/style|uint|0"
    "/plugins/plugin-14|string|actions"
    "/plugins/plugin-15|string|xfce4-clipman-plugin"
  )

  local entry prop type val
  for entry in "${props[@]}"; do
    IFS='|' read -r prop type val <<< "$entry"
    xfconf_set "$ch" "$prop" "$type" "$val"
  done

  xfconf_set_array "$ch" "/panels/panel-1/plugin-ids" "int" \
    1 15 2 3 4 5 6 8 9 10 11 12 13 14

  if (( ! DRY_RUN )) && [[ -z "${PROVISION_NO_RELOAD:-}" && -n "${DISPLAY:-}" ]] \
     && pgrep -u "${USER:-$(id -un)}" -x xfce4-panel >/dev/null 2>&1; then
    log_info "Reloading running xfce4-panel..."
    xfce4-panel -r >/dev/null 2>&1 || true
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_panel
fi
