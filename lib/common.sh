#!/usr/bin/env bash
# Shared helpers for provision-xubuntu scripts and modules.

if [[ "${_PROVISION_COMMON_LOADED:-0}" == "1" ]]; then
  return 0
fi
_PROVISION_COMMON_LOADED=1

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${COMMON_DIR}/.." && pwd)"

DRY_RUN="${DRY_RUN:-0}"
OFFLINE="${OFFLINE:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
DO_BACKUP="${DO_BACKUP:-1}"
ONLY_MODULES="${ONLY_MODULES:-}"
SKIP_MODULES="${SKIP_MODULES:-}"

_load_local_config() {
  local saved_redshift_set=0 saved_redshift=""
  if [[ -n "${REDSHIFT_LOCATION+x}" ]]; then
    saved_redshift_set=1
    saved_redshift="${REDSHIFT_LOCATION}"
  fi
  local cfg_file
  for cfg_file in "${REPO_ROOT}/config.local" "${XDG_CONFIG_HOME:-${HOME}/.config}/provision-xubuntu/config.local"; do
    if [[ "${PROVISION_IGNORE_REPO_LOCAL:-0}" == "1" && "$cfg_file" == "${REPO_ROOT}/config.local" ]]; then
      continue
    fi
    if [[ -r "$cfg_file" ]]; then
      # shellcheck disable=SC1090
      source "$cfg_file"
    fi
  done
  if (( saved_redshift_set )); then
    REDSHIFT_LOCATION="${saved_redshift}"
  fi
}
_load_local_config
REDSHIFT_LOCATION="${REDSHIFT_LOCATION:-}"

readonly ALL_MODULES=(
  themes_and_fonts
  xfwm4
  appearance
  shortcuts
  input
  panel
  session_and_power
  autostart
  apps
  airgradient
)

log_info()  { printf '[INFO]  %s\n' "$*"; }
log_warn()  { printf '[WARN]  %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
log_dry()   { printf '[DRY]   %s\n' "$*"; }

config_home() {
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}"
}

data_home() {
  printf '%s\n' "${XDG_DATA_HOME:-${HOME}/.local/share}"
}

run_cmd() {
  if (( DRY_RUN )); then
    log_dry "$*"
    return 0
  fi
  "$@"
}

csv_contains() {
  local list="${1:-}" item="$2"
  [[ -n "$list" ]] || return 1
  local IFS=',' entry
  for entry in $list; do
    if [[ "$entry" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

is_valid_module() {
  local target="$1" mod
  for mod in "${ALL_MODULES[@]}"; do
    if [[ "$mod" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

validate_module_csv() {
  local csv="${1:-}" allow_deps="${2:-0}"
  [[ -n "$csv" ]] || return 0
  local IFS=',' entry
  for entry in $csv; do
    if [[ "$allow_deps" == "1" && "$entry" == "deps" ]]; then
      continue
    fi
    if ! is_valid_module "$entry"; then
      log_error "Unknown module: '$entry'. Valid modules: ${ALL_MODULES[*]}"
      return 1
    fi
  done
}

should_run_module() {
  local mod="$1"
  if [[ -n "$ONLY_MODULES" ]] && ! csv_contains "$ONLY_MODULES" "$mod"; then
    return 1
  fi
  if csv_contains "$SKIP_MODULES" "$mod"; then
    return 1
  fi
  return 0
}

xfconf_set() {
  local channel="$1" prop="$2" type="$3" val="$4"
  if (( DRY_RUN )); then
    log_dry "xfconf-query -c $channel -p $prop -n -t $type --set=$val"
    return 0
  fi
  # Always use --set=VALUE so negative ints (-1, -3) are not parsed as flags.
  if ! xfconf-query --channel "$channel" --property "$prop" \
       --create --type "$type" "--set=$val" 2>/dev/null; then
    xfconf-query --channel "$channel" --property "$prop" --reset 2>/dev/null || true
    xfconf-query --channel "$channel" --property "$prop" \
      --create --type "$type" "--set=$val"
  fi
}

xfconf_set_array() {
  local channel="$1" prop="$2" type="$3"
  shift 3
  if (( DRY_RUN )); then
    log_dry "xfconf-query -c $channel -p $prop -n -a (-t $type): $*"
    return 0
  fi
  local args=() val
  for val in "$@"; do
    args+=(--type "$type" "--set=$val")
  done
  xfconf-query --channel "$channel" --property "$prop" --reset 2>/dev/null || true
  xfconf-query --channel "$channel" --property "$prop" --create --force-array "${args[@]}"
}

xfconf_reset() {
  local channel="$1" prop="$2"
  if (( DRY_RUN )); then
    log_dry "xfconf-query -c $channel -p $prop --reset --recursive"
    return 0
  fi
  xfconf-query --channel "$channel" --property "$prop" --reset --recursive 2>/dev/null || true
}

gsettings_set() {
  local schema="$1" key="$2" val="$3"
  if (( DRY_RUN )); then
    log_dry "gsettings set $schema $key $val"
    return 0
  fi
  if ! command -v gsettings >/dev/null 2>&1; then
    log_warn "gsettings not installed; skipping $schema $key"
    return 0
  fi
  local schemas
  schemas="$(gsettings list-schemas 2>/dev/null || true)"
  if [[ $'\n'"${schemas}"$'\n' != *$'\n'"${schema}"$'\n'* ]]; then
    log_warn "gsettings schema $schema not found; skipping $key"
    return 0
  fi
  if ! gsettings set "$schema" "$key" "$val" 2>/dev/null; then
    log_warn "gsettings set $schema $key $val failed; continuing"
  fi
}

ini_set() {
  local file="$1" section="$2" key="$3" val="$4"
  if (( DRY_RUN )); then
    log_dry "ini_set $file [$section] $key=$val"
    return 0
  fi
  local dir tmp
  dir="$(dirname "$file")"
  mkdir -p "$dir"
  if [[ ! -f "$file" ]]; then
    printf '[%s]\n%s=%s\n' "$section" "$key" "$val" > "$file"
    return 0
  fi
  tmp="$(mktemp "${dir}/.tmp.XXXXXX")"
  INI_SEC="$section" INI_KEY="$key" INI_VAL="$val" awk '
    BEGIN {
      sec = ENVIRON["INI_SEC"]
      key = ENVIRON["INI_KEY"]
      val = ENVIRON["INI_VAL"]
      in_sec = 0
      seen_sec = 0
      done = 0
    }
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      header = $0
      sub(/^[[:space:]]*\[/, "", header)
      sub(/\][[:space:]]*$/, "", header)
      if (in_sec && !done) {
        print key "=" val
        done = 1
      }
      in_sec = (header == sec)
      if (in_sec) seen_sec = 1
      print $0
      next
    }
    {
      if (in_sec && !done && $0 !~ /^[[:space:]]*[#;]/) {
        eq = index($0, "=")
        if (eq > 0) {
          lhs = substr($0, 1, eq - 1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
          if (lhs == key) {
            print key "=" val
            done = 1
            next
          }
        }
      }
      print $0
    }
    END {
      if (!seen_sec) {
        if (NR > 0) print ""
        print "[" sec "]"
        print key "=" val
      } else if (in_sec && !done) {
        print key "=" val
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

kv_set() {
  local file="$1" key="$2" val="$3"
  if (( DRY_RUN )); then
    log_dry "kv_set $file $key=$val"
    return 0
  fi
  local dir tmp
  dir="$(dirname "$file")"
  mkdir -p "$dir"
  if [[ ! -f "$file" ]]; then
    printf '%s=%s\n' "$key" "$val" > "$file"
    return 0
  fi
  tmp="$(mktemp "${dir}/.tmp.XXXXXX")"
  KV_KEY="$key" KV_VAL="$val" awk '
    BEGIN {
      key = ENVIRON["KV_KEY"]
      val = ENVIRON["KV_VAL"]
      done = 0
    }
    {
      if (!done && $0 !~ /^[[:space:]]*[#;]/) {
        eq = index($0, "=")
        if (eq > 0) {
          lhs = substr($0, 1, eq - 1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
          if (lhs == key) {
            print key "=" val
            done = 1
            next
          }
        }
      }
      print $0
    }
    END {
      if (!done) {
        print key "=" val
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

write_desktop_file() {
  local path="$1" content="$2"
  if (( DRY_RUN )); then
    log_dry "write desktop entry: $path"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

install_kanagawa_from_snapshot() {
  local src="${REPO_ROOT}/assets/themes/Kanagawa-BL"
  local dest="${HOME}/.themes/Kanagawa-BL"
  if [[ ! -d "${src}/gtk-3.0" ]]; then
    log_error "Vendored Kanagawa-BL snapshot missing at ${src}"
    return 1
  fi
  if (( DRY_RUN )); then
    log_dry "copy snapshot ${src} -> ${dest}"
    return 0
  fi
  mkdir -p "$dest"
  cp -a "${src}/." "${dest}/"
  log_info "Installed Kanagawa-BL theme from offline snapshot to ${dest}"
}

install_azeret_from_snapshot() {
  local src="${REPO_ROOT}/assets/fonts/AzeretMono"
  local dest
  dest="$(data_home)/fonts/AzeretMono"
  if [[ ! -f "${src}/AzeretMono-Regular.ttf" ]]; then
    log_error "Vendored Azeret Mono snapshot missing at ${src}"
    return 1
  fi
  if (( DRY_RUN )); then
    log_dry "copy snapshot ${src}/*.ttf -> ${dest}/ && fc-cache -f"
    return 0
  fi
  mkdir -p "$dest"
  cp -f "${src}"/*.ttf "$dest/"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$(data_home)/fonts" >/dev/null 2>&1 || true
  fi
  log_info "Installed Azeret Mono static TTFs from offline snapshot to ${dest}"
}
