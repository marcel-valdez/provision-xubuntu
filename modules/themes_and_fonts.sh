#!/usr/bin/env bash
# Module: themes_and_fonts — ensures no-titlebar themerc, Kanagawa-BL, and Azeret Mono exist.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_themes_and_fonts() {
  log_info "Configuring themes_and_fonts..."

  local no_titlebar_dir="${HOME}/.themes/no-titlebar/xfwm4"
  local themerc="${no_titlebar_dir}/themerc"
  if (( DRY_RUN )); then
    log_dry "create 0-byte borderless xfwm4 themerc at ${themerc}"
  else
    mkdir -p "$no_titlebar_dir"
    : > "$themerc"
  fi

  if [[ ! -d "${HOME}/.themes/Kanagawa-BL/gtk-3.0" ]]; then
    install_kanagawa_from_snapshot
  else
    log_info "Kanagawa-BL already present at ${HOME}/.themes/Kanagawa-BL"
  fi

  local font_dest
  font_dest="$(data_home)/fonts/AzeretMono"
  if [[ ! -f "${font_dest}/AzeretMono-Regular.ttf" && ! -f "${HOME}/.fonts/static/AzeretMono-Regular.ttf" ]]; then
    install_azeret_from_snapshot
  else
    log_info "Azeret Mono already installed"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_themes_and_fonts
fi
