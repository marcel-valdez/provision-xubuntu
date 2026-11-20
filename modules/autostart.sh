#!/usr/bin/env bash
# Module: autostart — picom v12 compositor, Rofi window watcher, Redshift, and hidden bloat entries.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_autostart() {
  log_info "Configuring autostart..."

  local autostart_dir
  autostart_dir="$(config_home)/autostart"

  write_desktop_file "${autostart_dir}/Picom Compositor.desktop" "[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
Name=Picom Compositor
Comment=Lightweight X11 compositor replacing legacy compton
Exec=/usr/bin/picom --backend glx --vsync --unredir-if-possible --unredir-if-possible-delay 10 --no-fading-openclose --no-fading-destroyed-argb
OnlyShowIn=XFCE;
RunHook=0
StartupNotify=false
Terminal=false
Hidden=false"

  # Avoid Compton and Picom racing if migrating an existing desktop.
  if [[ -f "${autostart_dir}/Compton Compositor.desktop" ]]; then
    ini_set "${autostart_dir}/Compton Compositor.desktop" "Desktop Entry" "Hidden" "true"
  fi

  write_desktop_file "${autostart_dir}/Rofi Window Watcher Daemon.desktop" "[Desktop Entry]
Encoding=UTF-8
Version=0.9.4
Type=Application
Name=Rofi Window Watcher Daemon
Comment=Tracks active window history for rofi-window-switcher
Exec=${HOME}/projects/x-window-shortcuts/window-watcher-daemon.sh
OnlyShowIn=XFCE;
RunHook=0
StartupNotify=false
Terminal=false
Hidden=false"

  if [[ -n "${REDSHIFT_LOCATION:-}" ]]; then
    write_desktop_file "${autostart_dir}/redshift-gtk.desktop" "[Desktop Entry]
Version=1.0
Name=Redshift
GenericName=Color temperature adjustment
Comment=Color temperature adjustment tool
Exec=/usr/bin/redshift -l ${REDSHIFT_LOCATION}
Icon=redshift
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
Hidden=false
X-GNOME-Autostart-enabled=true
RunHook=0"
  else
    log_warn "REDSHIFT_LOCATION is unset; skipping redshift-gtk.desktop (set via --redshift-location, REDSHIFT_LOCATION env, or config.local)."
  fi

  local hidden_entry
  local -a disabled_entries=(
    "xfce4-screensaver.desktop"
    "light-locker.desktop"
    "geoclue-demo-agent.desktop"
    "org.gnome.DejaDup.Monitor.desktop"
    "org.gnome.Evolution-alarm-notify.desktop"
  )
  for hidden_entry in "${disabled_entries[@]}"; do
    write_desktop_file "${autostart_dir}/${hidden_entry}" "[Desktop Entry]
Hidden=true"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_autostart
fi
