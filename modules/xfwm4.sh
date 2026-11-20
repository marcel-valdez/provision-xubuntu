#!/usr/bin/env bash
# Module: xfwm4 — borderless window manager settings, focus, tiling, workspaces, shadows off.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_xfwm4() {
  log_info "Configuring xfwm4..."

  local ch="xfwm4"
  local -a props=(
    # Borderless / titlebar layout
    "/general/theme|string|no-titlebar"
    "/general/borderless_maximize|bool|true"
    "/general/titleless_maximize|bool|true"
    "/general/frame_border_top|int|0"
    "/general/show_app_icon|bool|false"
    "/general/button_layout|string|O|SHMC"
    "/general/button_offset|int|0"
    "/general/button_spacing|int|0"
    "/general/title_alignment|string|center"
    "/general/title_font|string|Sans Bold 9"
    "/general/full_width_title|bool|true"
    "/general/title_horizontal_offset|int|0"
    "/general/title_vertical_offset_active|int|0"
    "/general/title_vertical_offset_inactive|int|0"
    "/general/title_shadow_active|string|false"
    "/general/title_shadow_inactive|string|false"
    "/general/maximized_offset|int|0"

    # Focus & interaction
    "/general/activate_action|string|switch"
    "/general/click_to_focus|bool|true"
    "/general/focus_delay|int|250"
    "/general/focus_hint|bool|true"
    "/general/focus_new|bool|true"
    "/general/prevent_focus_stealing|bool|false"
    "/general/raise_delay|int|250"
    "/general/raise_on_click|bool|true"
    "/general/raise_on_focus|bool|false"
    "/general/raise_with_any_button|bool|true"
    "/general/easy_click|string|None"
    "/general/double_click_action|string|maximize"
    "/general/double_click_distance|int|5"
    "/general/double_click_time|int|250"
    "/general/mousewheel_rollup|bool|true"
    "/general/placement_mode|string|center"
    "/general/placement_ratio|int|20"

    # Snapping, tiling & move/resize
    "/general/box_move|bool|true"
    "/general/box_resize|bool|true"
    "/general/snap_resist|bool|false"
    "/general/snap_to_border|bool|true"
    "/general/snap_to_windows|bool|true"
    "/general/snap_width|int|5"
    "/general/tile_on_move|bool|true"

    # Workspaces & window cycling
    "/general/workspace_count|int|5"
    "/general/scroll_workspaces|bool|false"
    "/general/toggle_workspaces|bool|false"
    "/general/wrap_cycle|bool|false"
    "/general/wrap_layout|bool|false"
    "/general/wrap_resistance|int|10"
    "/general/wrap_windows|bool|false"
    "/general/wrap_workspaces|bool|false"
    "/general/cycle_apps_only|bool|false"
    "/general/cycle_draw_frame|bool|true"
    "/general/cycle_hidden|bool|true"
    "/general/cycle_minimized|bool|false"
    "/general/cycle_minimum|bool|false"
    "/general/cycle_preview|bool|false"
    "/general/cycle_raise|bool|false"
    "/general/cycle_tabwin_mode|int|1"
    "/general/cycle_workspaces|bool|false"

    # Compositing (off; delegated to picom), shadows, opacity & misc
    "/general/use_compositing|bool|false"
    "/general/vblank_mode|string|auto"
    "/general/unredirect_overlays|bool|true"
    "/general/show_dock_shadow|bool|false"
    "/general/show_frame_shadow|bool|false"
    "/general/show_popup_shadow|bool|false"
    "/general/shadow_delta_height|int|0"
    "/general/shadow_delta_width|int|0"
    "/general/shadow_delta_x|int|0"
    "/general/shadow_delta_y|int|-3"
    "/general/shadow_opacity|int|50"
    "/general/frame_opacity|int|100"
    "/general/inactive_opacity|int|100"
    "/general/move_opacity|int|100"
    "/general/popup_opacity|int|100"
    "/general/resize_opacity|int|100"
    "/general/horiz_scroll_opacity|bool|false"
    "/general/urgent_blink|bool|false"
    "/general/repeat_urgent_blink|bool|false"
    "/general/zoom_desktop|bool|true"
    "/general/zoom_pointer|bool|true"
  )

  local entry prop type val
  for entry in "${props[@]}"; do
    IFS='|' read -r prop type val <<< "$entry"
    xfconf_set "$ch" "$prop" "$type" "$val"
  done

  xfconf_set_array "$ch" "/general/workspace_names" "string" \
    "Workspace 1" "Workspace 2" "Workspace 3" "Workspace 4" "Workspace 5"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_xfwm4
fi
