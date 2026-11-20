#!/usr/bin/env bash
# Standalone unprivileged XFCE4 configuration orchestrator using xfconf-query.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

RAW_ARGS=("$@")

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Apply all XFCE4 productivity, theme, window-manager, panel, and autostart settings.

Options:
  --dry-run                       Print commands without modifying configuration
  --only <m1,m2,...>              Run only the specified modules
  --skip <m1,m2,...>              Skip the specified modules
  --no-backup                     Do not back up existing xfconf XML files first
  --offline                       Offline mode (same as snapshot-only for themes_and_fonts)
  --redshift-location <lat:lon>   Override Redshift coordinates (default: ${REDSHIFT_LOCATION:-unset; configure via config.local or REDSHIFT_LOCATION})
  -h, --help                      Show this help message

Modules:
  ${ALL_MODULES[*]}
EOF
}

require_arg() {
  local opt="$1" remaining="$2"
  if (( remaining < 2 )); then
    log_error "Option ${opt} requires an argument."
    exit 1
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      DRY_RUN=1; shift ;;
    --no-backup)
      DO_BACKUP=0; shift ;;
    --offline)
      OFFLINE=1; shift ;;
    --only)
      require_arg "$1" "$#"
      ONLY_MODULES="$2"; shift 2 ;;
    --only=*)
      ONLY_MODULES="${1#*=}"; shift ;;
    --skip)
      require_arg "$1" "$#"
      SKIP_MODULES="$2"; shift 2 ;;
    --skip=*)
      SKIP_MODULES="${1#*=}"; shift ;;
    --redshift-location)
      require_arg "$1" "$#"
      REDSHIFT_LOCATION="$2"; shift 2 ;;
    --redshift-location=*)
      REDSHIFT_LOCATION="${1#*=}"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      log_error "Unknown option: $1"
      usage >&2
      exit 1 ;;
  esac
done

validate_module_csv "$ONLY_MODULES" 0
validate_module_csv "$SKIP_MODULES" 0

# Re-exec inside a temporary D-Bus session when running headlessly (e.g. over SSH)
# so xfconfd can initialize and flush XML files cleanly.
if (( ! DRY_RUN )) && [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  if ! command -v dbus-run-session >/dev/null 2>&1; then
    log_error "DBUS_SESSION_BUS_ADDRESS is unset and dbus-run-session was not found."
    exit 1
  fi
  log_info "No D-Bus session detected; re-launching inside dbus-run-session..."
  exec dbus-run-session -- "$0" "${RAW_ARGS[@]}"
fi

backup_xfconf_xml() {
  (( DO_BACKUP )) || return 0
  local xml_dir
  xml_dir="$(config_home)/xfce4/xfconf/xfce-perchannel-xml"
  [[ -d "$xml_dir" ]] || return 0

  shopt -s nullglob
  local xml_files=("${xml_dir}"/*.xml)
  shopt -u nullglob
  (( ${#xml_files[@]} > 0 )) || return 0

  local backup_root base_ts backup_dir suffix=1
  backup_root="$(config_home)/xfce4/xfconf/backups"
  base_ts="$(date +%Y%m%d-%H%M%S)"
  backup_dir="${backup_root}/${base_ts}"
  while [[ -e "$backup_dir" ]]; do
    backup_dir="${backup_root}/${base_ts}-${suffix}"
    (( suffix++ ))
  done

  if (( DRY_RUN )); then
    log_dry "backup ${#xml_files[@]} xfconf XML files to ${backup_dir}"
    return 0
  fi

  mkdir -p "$backup_dir"
  cp -a "${xml_files[@]}" "${backup_dir}/"
  log_info "Backed up ${#xml_files[@]} existing xfconf XML files to ${backup_dir}"
}

main() {
  if (( ! DRY_RUN )) && ! command -v xfconf-query >/dev/null 2>&1; then
    log_error "xfconf-query is required but not installed (run ./install-deps.sh first)."
    exit 1
  fi

  backup_xfconf_xml

  local mod
  for mod in "${ALL_MODULES[@]}"; do
    if should_run_module "$mod"; then
      source "${SCRIPT_DIR}/modules/${mod}.sh"
      "run_${mod}"
    else
      log_info "Skipping module: ${mod}"
    fi
  done

  log_info "XFCE configuration complete."
}

main
