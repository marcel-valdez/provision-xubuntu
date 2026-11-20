#!/usr/bin/env bash
# Module: shortcuts — resets custom shortcut trees and configures xfwm4 + command bindings.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_shortcuts() {
  log_info "Configuring shortcuts..."

  local ch="xfce4-keyboard-shortcuts"
  local xws_dir="${HOME}/projects/x-window-shortcuts"
  if [[ ! -x "${xws_dir}/x-window-move" ]]; then
    log_warn "x-window-shortcuts not found at ${xws_dir}; shortcuts will still be written."
  fi

  xfconf_reset "$ch" "/commands/custom"
  xfconf_reset "$ch" "/xfwm4/custom"
  xfconf_set_array "$ch" "/providers" "string" "xfwm4" "commands"
  xfconf_set "$ch" "/commands/custom/override" "bool" "true"
  xfconf_set "$ch" "/xfwm4/custom/override" "bool" "true"

  local -a cmd_bindings=(
    "<Primary><Alt>l|xflock4"
    "<Super>l|xflock4"
    "<Primary><Alt>t|exo-open --launch TerminalEmulator"
    "XF86Display|xfce4-display-settings --minimal"
    "<Super>p|xfce4-display-settings --minimal"
    "XF86Mail|exo-open --launch MailReader"
    "XF86WWW|exo-open --launch WebBrowser"
    "Print|xfce4-screenshooter"
    "<Super>1|xfce4-popup-applicationsmenu"
    "<Super>2|xfce4-appfinder --collapsed"
    "<Super>3|rofi -show drun"
    "<Primary><Alt>f|rofi -show filebrowser"
    "<Super>m|xfdesktop --menu"
    "<Super>v|/usr/bin/xfce4-clipman-history"
    "ScrollUp|/usr/bin/xdotool click 4"
    "ScrollDown|/usr/bin/xdotool click 5"
    "<Super>Right|${xws_dir}/x-window-move right"
    "<Super>Left|${xws_dir}/x-window-move left"
    "<Super>Up|${xws_dir}/x-window-move up"
    "<Super>Down|${xws_dir}/x-window-move down"
    "<Super>k|${xws_dir}/x-window-move center"
    "<Primary><Super>Left|${xws_dir}/x-window-move left-screen"
    "<Primary><Super>Right|${xws_dir}/x-window-move right-screen"
    "<Alt>Tab|${xws_dir}/rofi-window-switcher"
  )

  local entry key cmd
  for entry in "${cmd_bindings[@]}"; do
    IFS='|' read -r key cmd <<< "$entry"
    xfconf_set "$ch" "/commands/custom/${key}" "string" "$cmd"
  done

  xfconf_set "$ch" "/commands/custom/<Super>2/startup-notify" "bool" "true"
  xfconf_set "$ch" "/commands/custom/<Super>3/startup-notify" "bool" "true"

  # Intentionally omits <Alt>F4 (replaced by <Shift><Alt>dollar) and
  # <Alt>Tab (delegated to rofi-window-switcher in /commands/custom).
  local -a wm_bindings=(
    "Left|left_key"
    "Right|right_key"
    "Up|up_key"
    "Down|down_key"
    "Escape|cancel_key"
    "<Alt>space|popup_menu_key"
    "<Super>Page_Up|maximize_window_key"
    "<Super>Page_Down|hide_window_key"
    "<Primary><Super>Page_Up|fullscreen_key"
    "<Super>d|show_desktop_key"
    "<Shift><Alt>dollar|close_window_key"
    "<Super>Tab|switch_application_key"
    "<Ctrl><Alt>Tab|null"
    "<Primary><Alt>Left|left_workspace_key"
    "<Primary><Alt>Right|right_workspace_key"
    "<Primary><Alt>Up|up_workspace_key"
    "<Primary><Alt>Down|down_workspace_key"
    "<Primary><Shift><Alt>Left|move_window_prev_workspace_key"
    "<Primary><Shift><Alt>Right|move_window_next_workspace_key"
    "<Primary><Shift><Alt>Up|move_window_up_key"
    "<Primary><Alt>1|workspace_1_key"
    "<Primary><Alt>2|workspace_2_key"
    "<Primary><Alt>3|workspace_3_key"
    "<Primary><Alt>4|workspace_4_key"
    "<Primary><Alt>5|workspace_5_key"
  )

  local action
  for entry in "${wm_bindings[@]}"; do
    IFS='|' read -r key action <<< "$entry"
    xfconf_set "$ch" "/xfwm4/custom/${key}" "string" "$action"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_shortcuts
fi
