#!/usr/bin/env bash
# Module: airgradient — installs airgradient-monitor systemd user unit and seeds config.json.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
fi

_default_airgradient_unit() {
  cat <<'EOF'
[Unit]
Description=AirGradient air-quality monitor and alert daemon
Documentation=https://api.airgradient.com/public/docs/api/v1/
StartLimitIntervalSec=0

[Service]
Type=notify
NotifyAccess=main
ExecStart=%h/.local/bin/airgradient-monitor -config %h/.config/airgradient-monitor/config.json
Restart=on-failure
RestartSec=30s
RestartPreventExitStatus=2
WatchdogSec=5min
TimeoutStartSec=30s
TimeoutStopSec=20s
UMask=0077
NoNewPrivileges=yes
MemoryMax=128M

[Install]
WantedBy=default.target
EOF
}

_default_airgradient_config() {
  cat <<'EOF'
{
  "api_token": "YOUR_AIRGRADIENT_API_TOKEN",
  "location_id": 210460,

  "poll_interval_sec": 60,
  "http_timeout_sec": 10,
  "max_backoff_sec": 300,

  "wake_start_hour": 7,
  "wake_end_hour": 23,
  "timezone": "",

  "cooldown_minutes": 45,
  "critical_cooldown_minutes": 45,
  "trigger_after_samples": 1,
  "clear_after_samples": 3,
  "notify_resolved": true,
  "stale_after_minutes": 15,

  "persist_state": true,
  "log_level": "info",

  "thresholds": {
    "rco2":      { "warning": [">=1000"],     "critical": [">=1600"],       "hysteresis": 50 },
    "pm02":      { "warning": [">=12"],       "critical": [">=35"],         "hysteresis": 2 },
    "tvocIndex": { "warning": [">=200"],      "critical": [">=350"],        "hysteresis": 15 },
    "rhum":      { "warning": ["<35", ">55"], "critical": ["<=20", ">=70"], "hysteresis": 2 },
    "atmp":      { "warning": ["<19", ">25"], "critical": [">=31"],         "hysteresis": 0.5 },
    "noxIndex":  { "warning": [],             "critical": [],               "hysteresis": 5 }
  },

  "notify": {
    "desktop": { "enabled": true, "app_name": "AirGradient Monitor", "replace_previous": true },
    "bell":    { "enabled": true, "command": ["paplay", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"] },
    "hooks": []
  },

  "panel": {
    "dashboard_url": "https://app.airgradient.com/dashboard?view=custom"
  }
}
EOF
}

run_airgradient() {
  log_info "Configuring airgradient..."

  local cfg repo_dir unit_dir unit_file ag_cfg_dir ag_cfg_file
  cfg="$(config_home)"
  repo_dir="${HOME}/projects/air_gradient_alarm_daemon"
  unit_dir="${cfg}/systemd/user"
  unit_file="${unit_dir}/airgradient-monitor.service"
  ag_cfg_dir="${cfg}/airgradient-monitor"
  ag_cfg_file="${ag_cfg_dir}/config.json"

  if (( DRY_RUN )); then
    log_dry "install systemd user unit -> ${unit_file}"
    if [[ ! -f "$ag_cfg_file" ]]; then
      log_dry "seed mode-600 default config -> ${ag_cfg_file}"
    else
      log_info "Existing ${ag_cfg_file} would be preserved."
    fi
    if [[ -x "${repo_dir}/deploy/xfce/airgradient-panel.sh" ]]; then
      log_dry "install AirGradient Xfce GenMon panel item via ${repo_dir}/deploy/xfce/airgradient-panel.sh"
    fi
    return 0
  fi

  mkdir -p "$unit_dir"
  if [[ -f "${repo_dir}/deploy/airgradient-monitor.service" ]]; then
    install -m 644 "${repo_dir}/deploy/airgradient-monitor.service" "$unit_file"
  else
    _default_airgradient_unit > "$unit_file"
    chmod 644 "$unit_file"
  fi

  install -d -m 700 "$ag_cfg_dir"
  if [[ ! -f "$ag_cfg_file" ]]; then
    if [[ -f "${repo_dir}/config.example.json" ]]; then
      install -m 600 "${repo_dir}/config.example.json" "$ag_cfg_file"
      # Explicitly wire paplay so critical alarms sound even with GTK event sounds disabled.
      if command -v python3 >/dev/null 2>&1; then
        AG_CFG_TMP="$ag_cfg_file" python3 -c '
import json, os
p = os.environ["AG_CFG_TMP"]
with open(p, "r", encoding="utf-8") as f:
    data = json.load(f)
bell = data.setdefault("notify", {}).setdefault("bell", {})
if bell.get("command") == []:
    bell["command"] = ["paplay", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]
with open(p, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
'
      else
        sed -i 's|"command": \[\]|"command": ["paplay", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]|' "$ag_cfg_file"
      fi
      chmod 600 "$ag_cfg_file"
    else
      _default_airgradient_config > "$ag_cfg_file"
      chmod 600 "$ag_cfg_file"
    fi
    log_info "Seeded ${ag_cfg_file} (mode 600). Set api_token before starting the service."
  else
    log_info "Preserving existing ${ag_cfg_file}."
  fi

  if [[ -z "${PROVISION_NO_RELOAD:-}" ]] && command -v systemctl >/dev/null 2>&1 \
     && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable airgradient-monitor.service >/dev/null 2>&1 || true
    if [[ -x "${HOME}/.local/bin/airgradient-monitor" ]] \
       && ! grep -Fq "YOUR_AIRGRADIENT_API_TOKEN" "$ag_cfg_file"; then
      systemctl --user restart airgradient-monitor.service
      log_info "Enabled and restarted airgradient-monitor.service."
    else
      log_info "Enabled airgradient-monitor.service (not started: configure api_token in ${ag_cfg_file}, then run 'systemctl --user start airgradient-monitor.service')."
    fi
  fi

  if [[ -z "${PROVISION_NO_RELOAD:-}" && -x "${repo_dir}/deploy/xfce/airgradient-panel.sh" \
     && -x "${HOME}/.local/bin/airgradient-monitor" ]] \
     && { [[ -e /usr/share/xfce4/panel/plugins/genmon.desktop || -e /usr/local/share/xfce4/panel/plugins/genmon.desktop ]]; }; then
    AIRGRADIENT_BIN="${HOME}/.local/bin/airgradient-monitor" \
      "${repo_dir}/deploy/xfce/airgradient-panel.sh" install \
      || log_warn "Could not install AirGradient Xfce panel item automatically."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_airgradient
fi
