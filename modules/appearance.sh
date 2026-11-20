#!/usr/bin/env bash
# Module: appearance — xsettings, dark mode (gsettings + GTK3/4), fonts, and Xft rendering.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_appearance() {
  log_info "Configuring appearance..."

  local ch="xsettings"
  local -a props=(
    "/Net/ThemeName|string|Kanagawa-BL"
    "/Net/IconThemeName|string|elementary-xfce"
    "/Net/CursorBlinkTime|int|721"
    "/Xft/DPI|int|-1"
    "/Xft/Antialias|int|1"
    "/Xft/Hinting|int|1"
    "/Xft/HintStyle|string|hintfull"
    "/Xft/RGBA|string|rgb"
    "/Gtk/FontName|string|Inter Display 12"
    "/Gtk/MonospaceFontName|string|Azeret Mono 10"
    "/Gtk/DecorationLayout|string|icon,menu:minimize,maximize,close"
    "/Gtk/ToolbarStyle|string|icons"
  )

  local entry prop type val
  for entry in "${props[@]}"; do
    IFS='|' read -r prop type val <<< "$entry"
    xfconf_set "$ch" "$prop" "$type" "$val"
  done

  local iface="org.gnome.desktop.interface"
  gsettings_set "$iface" "color-scheme" "prefer-dark"
  gsettings_set "$iface" "gtk-theme" "Kanagawa-BL"
  gsettings_set "$iface" "icon-theme" "elementary-xfce"
  gsettings_set "$iface" "font-name" "Inter Display 12"
  gsettings_set "$iface" "monospace-font-name" "Azeret Mono 10"

  local cfg
  cfg="$(config_home)"
  ini_set "${cfg}/gtk-3.0/settings.ini" "Settings" "gtk-application-prefer-dark-theme" "1"
  ini_set "${cfg}/gtk-4.0/settings.ini" "Settings" "gtk-application-prefer-dark-theme" "1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_appearance
fi
