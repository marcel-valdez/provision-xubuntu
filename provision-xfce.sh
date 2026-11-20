#!/usr/bin/env bash
# Top-level entrypoint delegating to install-deps.sh and configure-xfce.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

NO_PACKAGES=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Provision a fresh Xubuntu/XFCE4 workstation end-to-end by running:
  1. ./install-deps.sh    (apt packages, x-window-shortcuts clone, Kanagawa-BL/Azeret Mono)
  2. ./configure-xfce.sh  (pure xfconf-query + GTK/autostart/app setup)

Options:
  --dry-run                       Print actions without making changes
  --yes                           Non-interactive apt-get install (-y)
  --offline                       Skip downloads/clones; use vendored assets/ snapshots
  --no-packages                   Skip install-deps.sh (unprivileged config only)
  --no-backup                     Skip xfconf XML backup before configuring
  --only <m1,m2,...>              Run only the listed modules (also accepts 'deps')
  --skip <m1,m2,...>              Skip the listed modules (also accepts 'deps')
  --redshift-location <lat:lon>   Override Redshift coordinates (default: ${REDSHIFT_LOCATION:-unset; configure via config.local or REDSHIFT_LOCATION})
  -h, --help                      Show this help message

Modules:
  deps ${ALL_MODULES[*]}
EOF
}

require_arg() {
  local opt="$1" remaining="$2"
  if (( remaining < 2 )); then
    log_error "Option ${opt} requires an argument."
    exit 1
  fi
}

strip_csv_item() {
  local csv="$1" remove="$2" out="" IFS=',' entry
  for entry in $csv; do
    [[ "$entry" == "$remove" ]] && continue
    out="${out:+${out},}${entry}"
  done
  printf '%s\n' "$out"
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      DRY_RUN=1; shift ;;
    --yes)
      ASSUME_YES=1; shift ;;
    --offline)
      OFFLINE=1; shift ;;
    --no-packages)
      NO_PACKAGES=1; shift ;;
    --no-backup)
      DO_BACKUP=0; shift ;;
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

validate_module_csv "$ONLY_MODULES" 1
validate_module_csv "$SKIP_MODULES" 1

run_deps=1
if (( NO_PACKAGES )) || csv_contains "$SKIP_MODULES" "deps"; then
  run_deps=0
elif [[ -n "$ONLY_MODULES" ]] && ! csv_contains "$ONLY_MODULES" "deps"; then
  run_deps=0
fi

cfg_only="$(strip_csv_item "$ONLY_MODULES" "deps")"
cfg_skip="$(strip_csv_item "$SKIP_MODULES" "deps")"

run_cfg=1
if [[ -n "$ONLY_MODULES" && -z "$cfg_only" ]]; then
  run_cfg=0
fi

if (( run_deps )); then
  deps_args=()
  (( DRY_RUN )) && deps_args+=(--dry-run)
  (( ASSUME_YES )) && deps_args+=(--yes)
  (( OFFLINE )) && deps_args+=(--offline)
  log_info "Step 1/2: Running install-deps.sh..."
  "${SCRIPT_DIR}/install-deps.sh" "${deps_args[@]}"
else
  log_info "Step 1/2: Skipping install-deps.sh."
fi

if (( run_cfg )); then
  cfg_args=()
  (( DRY_RUN )) && cfg_args+=(--dry-run)
  (( OFFLINE )) && cfg_args+=(--offline)
  (( ! DO_BACKUP )) && cfg_args+=(--no-backup)
  [[ -n "$cfg_only" ]] && cfg_args+=(--only "$cfg_only")
  [[ -n "$cfg_skip" ]] && cfg_args+=(--skip "$cfg_skip")
  [[ -n "$REDSHIFT_LOCATION" ]] && cfg_args+=(--redshift-location "$REDSHIFT_LOCATION")
  log_info "Step 2/2: Running configure-xfce.sh..."
  "${SCRIPT_DIR}/configure-xfce.sh" "${cfg_args[@]}"
else
  log_info "Step 2/2: Skipping configure-xfce.sh (--only deps)."
fi
