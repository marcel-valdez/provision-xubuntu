#!/usr/bin/env bash
# Module: input — keyboard repeat/NumLock and MoErgo Glove80 pointer acceleration (omits MouseKeys).

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

run_input() {
  log_info "Configuring input..."

  xfconf_set "keyboards" "/Default/KeyRepeat" "bool" "true"
  xfconf_set "keyboards" "/Default/KeyRepeat/Delay" "int" "250"
  xfconf_set "keyboards" "/Default/KeyRepeat/Rate" "int" "100"
  xfconf_set "keyboards" "/Default/Numlock" "bool" "true"

  xfconf_set "pointers" "/MoErgo_Glove80_Left_Mouse/RightHanded" "bool" "true"
  xfconf_set "pointers" "/MoErgo_Glove80_Left_Mouse/Threshold" "int" "1"
  xfconf_set "pointers" "/MoErgo_Glove80_Left_Mouse/Acceleration" "double" "10"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_input
fi
