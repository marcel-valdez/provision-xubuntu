#!/usr/bin/env bash
# Installs apt dependencies, clones ~/projects/x-window-shortcuts if missing,
# and installs Kanagawa-BL + Azeret Mono (download-first with offline snapshot fallback).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SKIP_APT=0
SKIP_CLONE=0
SKIP_ASSETS=0

_CLEANUP_DIRS=()
_cleanup_tmp() {
  if (( ${#_CLEANUP_DIRS[@]} > 0 )); then
    rm -rf "${_CLEANUP_DIRS[@]}" 2>/dev/null || true
  fi
}
trap _cleanup_tmp EXIT

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Ubuntu/XFCE dependencies, x-window-shortcuts, and non-apt theme/font assets.

Options:
  --dry-run      Print actions without changing anything
  --yes          Pass -y to apt-get install
  --offline      Skip network downloads; use vendored assets/ snapshots only
  --skip-apt     Skip apt package installation
  --skip-clone   Skip cloning ~/projects/x-window-shortcuts
  --skip-assets  Skip installing Kanagawa-BL and Azeret Mono
  -h, --help     Show this help message
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)     DRY_RUN=1; shift ;;
    --yes)         ASSUME_YES=1; shift ;;
    --offline)     OFFLINE=1; shift ;;
    --skip-apt)    SKIP_APT=1; shift ;;
    --skip-clone)  SKIP_CLONE=1; shift ;;
    --skip-assets) SKIP_ASSETS=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)
      log_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
  esac
done

install_apt_packages() {
  if (( SKIP_APT )); then
    log_info "Skipping apt package installation (--skip-apt)."
    return 0
  fi
  if ! command -v dpkg-query >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
    log_warn "apt-get/dpkg-query unavailable; skipping apt packages."
    return 0
  fi

  local -a required_packages=(
    xfconf
    exo-utils
    xfce4-appfinder
    xfce4-clipman
    xfce4-clipman-plugin
    xfce4-notifyd
    xfce4-screenshooter
    elementary-xfce-icon-theme
    fonts-inter
    rofi
    xdotool
    wmctrl
    bc
    x11-utils
    x11-xserver-utils
    libnotify-bin
    picom
    xscreensaver
    redshift
    sound-theme-freedesktop
    pulseaudio-utils
    xfce4-genmon-plugin
    zenity
    curl
    git
    fontconfig
  )

  if ! command -v go >/dev/null 2>&1; then
    required_packages+=(golang-go)
  fi

  local -a missing_pkgs=()
  local pkg status
  for pkg in "${required_packages[@]}"; do
    status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
    if [[ "$status" != "install ok installed" ]]; then
      missing_pkgs+=("$pkg")
    fi
  done

  if (( ${#missing_pkgs[@]} == 0 )); then
    log_info "All ${#required_packages[@]} required apt packages are already installed."
    return 0
  fi

  log_info "Missing apt packages (${#missing_pkgs[@]}): ${missing_pkgs[*]}"
  if (( OFFLINE )); then
    log_warn "Offline mode enabled; cannot install missing apt packages."
    return 0
  fi

  local -a apt_flags=()
  (( ASSUME_YES )) && apt_flags=(-y)
  run_cmd sudo apt-get update
  run_cmd sudo apt-get install "${apt_flags[@]}" "${missing_pkgs[@]}"
}

clone_git_repo() {
  local name="$1" target="$2" ssh_url="$3" https_url="$4"
  if (( SKIP_CLONE )); then
    log_info "Skipping ${name} clone (--skip-clone)."
    return 0
  fi
  if [[ -d "$target" ]]; then
    log_info "${name} already present at ${target}."
    return 0
  fi
  if (( OFFLINE )); then
    log_warn "Offline mode enabled; skipping clone of ${name} into ${target}."
    return 0
  fi
  if (( DRY_RUN )); then
    log_dry "git clone ${name} -> ${target}"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
       git clone "$ssh_url" "$target" 2>/dev/null; then
    log_info "Cloned ${name} via SSH to ${target}."
    return 0
  fi
  if GIT_TERMINAL_PROMPT=0 git clone "$https_url" "$target" 2>/dev/null; then
    log_info "Cloned ${name} via HTTPS to ${target}."
    return 0
  fi
  log_warn "Could not clone ${name} automatically; clone it later into ${target}."
  return 1
}

clone_x_window_shortcuts() {
  clone_git_repo \
    "x-window-shortcuts" \
    "${HOME}/projects/x-window-shortcuts" \
    "git@github.com:marcel-valdez/x-window-shortcuts.git" \
    "https://github.com/marcel-valdez/x-window-shortcuts.git" || true
}

clone_and_build_airgradient() {
  local target="${HOME}/projects/air_gradient_alarm_daemon"
  local bin_dest="${HOME}/.local/bin/airgradient-monitor"

  clone_git_repo \
    "air_gradient_alarm_daemon" \
    "$target" \
    "git@github.com:marcel-valdez/air_gradient_alarm_daemon.git" \
    "https://github.com/marcel-valdez/air_gradient_alarm_daemon.git" || true

  if (( DRY_RUN )) && [[ ! -d "$target" ]]; then
    log_dry "go build ./cmd/airgradient-monitor && install -Dm755 bin/airgradient-monitor ${bin_dest}"
    return 0
  fi
  if [[ ! -d "$target" ]]; then
    log_warn "air_gradient_alarm_daemon not present at ${target}; skipping build."
    return 0
  fi
  if ! command -v go >/dev/null 2>&1; then
    log_warn "go toolchain unavailable; skipping build of airgradient-monitor."
    return 0
  fi
  if (( DRY_RUN )); then
    log_dry "build airgradient-monitor in ${target} -> ${bin_dest}"
    return 0
  fi

  local version ldflags
  version="$(git -C "$target" describe --tags --always --dirty 2>/dev/null || echo dev)"
  ldflags="-s -w -X main.version=${version}"
  if (cd "$target" && CGO_ENABLED=0 go build -trimpath -ldflags "$ldflags" -o bin/airgradient-monitor ./cmd/airgradient-monitor); then
    install -Dm755 "${target}/bin/airgradient-monitor" "$bin_dest"
    log_info "Built and installed airgradient-monitor to ${bin_dest}"
  else
    log_warn "Failed to build airgradient-monitor in ${target}"
  fi
}

try_download_kanagawa() {
  local dest="${HOME}/.themes/Kanagawa-BL"
  local tmp candidate=""
  tmp="$(mktemp -d)"
  _CLEANUP_DIRS+=("$tmp")

  if ! GIT_TERMINAL_PROMPT=0 timeout 45 git clone --depth=1 --quiet \
       "https://github.com/Fausto-Korpsvart/Kanagawa-GKT-Theme.git" "${tmp}/repo" 2>/dev/null; then
    return 1
  fi

  # Look for a borderless dark Kanagawa GTK3 theme dir upstream.
  while IFS= read -r dir; do
    if [[ "$dir" == *Kanagawa* && ( "$dir" == *BL* || "$dir" == *Borderless* ) && "$dir" != *Light* ]]; then
      candidate="$dir"
      break
    fi
  done < <(find "${tmp}/repo" -maxdepth 4 -type d -exec test -d '{}/gtk-3.0' -a -d '{}/xfwm4' \; -print 2>/dev/null)

  [[ -n "$candidate" ]] || return 1

  mkdir -p "$dest"
  cp -a "${candidate}/." "${dest}/"
  log_info "Downloaded and installed Kanagawa-BL theme from upstream GitHub to ${dest}."
  return 0
}

try_download_azeret() {
  local dest
  dest="$(data_home)/fonts/AzeretMono"
  local tmp
  tmp="$(mktemp -d)"
  _CLEANUP_DIRS+=("$tmp")

  if ! GIT_TERMINAL_PROMPT=0 timeout 45 git clone --depth=1 --quiet \
       "https://github.com/displaay/Azeret.git" "${tmp}/repo" 2>/dev/null; then
    return 1
  fi

  local -a ttfs=()
  while IFS= read -r -d '' f; do
    [[ -s "$f" ]] && ttfs+=("$f")
  done < <(find "${tmp}/repo" -type f -name 'AzeretMono-*.ttf' ! -name '*Variable*' -print0 2>/dev/null)

  (( ${#ttfs[@]} >= 10 )) || return 1

  mkdir -p "$dest"
  cp -f "${ttfs[@]}" "$dest/"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$(data_home)/fonts" >/dev/null 2>&1 || true
  fi
  log_info "Downloaded and installed ${#ttfs[@]} Azeret Mono TTFs from upstream GitHub to ${dest}."
  return 0
}

install_visual_assets() {
  if (( SKIP_ASSETS )); then
    log_info "Skipping visual assets installation (--skip-assets)."
    return 0
  fi

  local theme_dest="${HOME}/.themes/Kanagawa-BL"
  if [[ -d "${theme_dest}/gtk-3.0" ]]; then
    log_info "Kanagawa-BL theme already present at ${theme_dest}."
  elif (( DRY_RUN )); then
    if (( OFFLINE )); then
      install_kanagawa_from_snapshot
    else
      log_dry "download Kanagawa-BL from upstream GitHub (fallback: assets/themes/Kanagawa-BL)"
    fi
  elif (( ! OFFLINE )) && try_download_kanagawa; then
    :
  else
    (( ! OFFLINE )) && log_warn "Kanagawa-BL download unavailable/unmatched; using offline snapshot."
    install_kanagawa_from_snapshot
  fi

  local font_dest
  font_dest="$(data_home)/fonts/AzeretMono"
  if [[ -f "${font_dest}/AzeretMono-Regular.ttf" || -f "${HOME}/.fonts/static/AzeretMono-Regular.ttf" ]]; then
    log_info "Azeret Mono static fonts already installed."
  elif (( DRY_RUN )); then
    if (( OFFLINE )); then
      install_azeret_from_snapshot
    else
      log_dry "download Azeret Mono from upstream GitHub (fallback: assets/fonts/AzeretMono)"
    fi
  elif (( ! OFFLINE )) && try_download_azeret; then
    :
  else
    (( ! OFFLINE )) && log_warn "Azeret Mono download unavailable/unmatched; using offline snapshot."
    install_azeret_from_snapshot
  fi
}

main() {
  install_apt_packages
  clone_x_window_shortcuts
  clone_and_build_airgradient
  install_visual_assets
}

main
