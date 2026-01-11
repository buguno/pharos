#!/bin/bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "Run as root: sudo $0"
fi

command -v apt >/dev/null 2>&1 || die "This script expects Debian/Raspberry Pi OS (apt)."

info "Running apt update..."
export DEBIAN_FRONTEND=noninteractive
apt update -y

info "Installing Kiwix (the kiwix-serve binary comes from the kiwix-tools package)..."
apt install -y --no-install-recommends kiwix-tools ca-certificates

info "Verifying installation..."
command -v kiwix-serve >/dev/null 2>&1 || die "kiwix-serve was not found after installation."

KIWIX_PORT="${KIWIX_PORT:-8080}"
ZIM_DIR="${ZIM_DIR:-/srv/kiwix/content}"
BITCOIN_ZIM_URL="https://download.kiwix.org/zim/other/bitcoin_en_all_maxi_2021-03.zim"
IFIXIT_ZIM_URL="https://download.kiwix.org/zim/ifixit/ifixit_en_all_2025-12.zim"

info "Ensuring ZIM directory exists: ${ZIM_DIR}"
mkdir -p "${ZIM_DIR}"

if ! command -v systemctl >/dev/null 2>&1; then
  die "systemctl not found. This script expects a systemd-based OS."
fi

setup_kiwix_systemd_service() {
  info "Creating/Updating kiwix-serve systemd service..."
  cat >/etc/default/kiwix-serve <<EOF
KIWIX_PORT=${KIWIX_PORT}
ZIM_DIR=${ZIM_DIR}
EOF

  cat >/etc/systemd/system/kiwix-serve.service <<EOF
[Unit]
Description=Kiwix offline content server
After=network-online.target
Wants=network-online.target
ConditionPathExistsGlob=${ZIM_DIR}/*.zim

[Service]
Restart=always
RestartSec=15
ExecStart=/usr/bin/bash -c "/usr/bin/kiwix-serve -p ${KIWIX_PORT} ${ZIM_DIR}/*.zim"

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable kiwix-serve >/dev/null
}

service_is_active() {
  systemctl is-active --quiet kiwix-serve.service
}

zim_present() {
  compgen -G "${ZIM_DIR}/*.zim" >/dev/null
}

start_or_restart_kiwix() {
  if ! zim_present; then
    info "No .zim files found in ${ZIM_DIR}. Not starting kiwix-serve yet."
    info "Tip: re-run this script and answer 'y' to download a ZIM (or copy your own .zim files)."
    return 0
  fi

  if service_is_active; then
    info "kiwix-serve is already running; restarting it to apply changes..."
    systemctl restart kiwix-serve.service
  else
    info "Starting kiwix-serve..."
    systemctl start kiwix-serve.service
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local answer=""

  if [[ ! -t 0 ]]; then
    return 1
  fi

  while true; do
    read -r -p "${prompt} [y/N] " answer
    case "${answer}" in
      [yY]|[yY][eE][sS]) return 0 ;;
      ""|[nN]|[nN][oO]) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

ensure_curl() {
  if ! command -v curl >/dev/null 2>&1; then
    info "curl not found; installing curl..."
    apt install -y --no-install-recommends curl
  fi
}

download_zim() {
  local url="$1"
  local file="${url##*/}"
  local path="${ZIM_DIR}/${file}"

  if [[ -f "${path}" ]]; then
    info "ZIM already exists, skipping: ${path}"
    return 0
  fi

  ensure_curl
  info "Downloading ZIM (this can take a while)..."
  info "Source: ${url}"
  info "Destination: ${path}"
  curl -L --fail --continue-at - --output "${path}" "${url}"
  return 2
}

configure_raspap_ssid() {
  local ssid="Pharos"
  local hostapd_conf="/etc/hostapd/hostapd.conf"

  if [[ ! -f "${hostapd_conf}" ]]; then
    info "hostapd.conf not found. RaspAP may use a different configuration location."
    return 0
  fi

  info "Configuring RaspAP SSID to: ${ssid}..."
  if grep -q "^ssid=" "${hostapd_conf}"; then
    sed -i "s/^ssid=.*/ssid=${ssid}/" "${hostapd_conf}"
  else
    echo "ssid=${ssid}" >> "${hostapd_conf}"
  fi

  info "SSID configured."
}

enable_raspap_ap_mode() {
  info "Enabling RaspAP Access Point mode..."
  info "WARNING: This will disconnect Wi-Fi client mode and may disconnect your SSH session."

  # Get SSID and password from hostapd.conf if available (before restarting)
  local hostapd_conf="/etc/hostapd/hostapd.conf"
  local ssid="Pharos"
  local wifi_password=""

  if [[ -f "${hostapd_conf}" ]]; then
    if grep -q "^ssid=" "${hostapd_conf}"; then
      ssid=$(grep "^ssid=" "${hostapd_conf}" | cut -d= -f2 | tr -d '"')
    fi
    if grep -q "^wpa_passphrase=" "${hostapd_conf}"; then
      wifi_password=$(grep "^wpa_passphrase=" "${hostapd_conf}" | cut -d= -f2 | tr -d '"')
    fi
  fi

  # Show connection information BEFORE starting AP mode
  info ""
  info "=== RaspAP Connection Information ==="
  info "Web Interface:"
  info "  URL: http://10.3.141.1"
  info "  Username: admin"
  info "  Password: secret"
  info ""
  info "Wi-Fi Hotspot:"
  info "  SSID: ${ssid}"
  if [[ -n "${wifi_password}" ]]; then
    info "  Password: ${wifi_password}"
  else
    info "  Password: (configured in RaspAP settings)"
  fi
  info ""
  info "Your SSH session will be disconnected as the Pi switches to AP mode."
  info "Connect to the '${ssid}' hotspot to access RaspAP web interface and Kiwix."
  info ""

  # Enable and start hostapd service
  if systemctl is-enabled hostapd >/dev/null 2>&1; then
    info "hostapd service already enabled."
  else
    systemctl enable hostapd >/dev/null 2>&1 || true
    info "hostapd service enabled."
  fi

  # Start/restart hostapd (this will activate AP mode and disconnect Wi-Fi client)
  systemctl restart hostapd >/dev/null 2>&1 || systemctl start hostapd >/dev/null 2>&1 || true

  info "Access Point mode enabled!"
}

setup_kiwix_systemd_service

start_or_restart_kiwix

downloaded_any=0

bitcoin_file="${BITCOIN_ZIM_URL##*/}"
bitcoin_path="${ZIM_DIR}/${bitcoin_file}"
if [[ -f "${bitcoin_path}" ]]; then
  info "Bitcoin ZIM already present, skipping prompt: ${bitcoin_path}"
else
  if prompt_yes_no "Do you want to download the Bitcoin wiki ZIM?"; then
    if download_zim "${BITCOIN_ZIM_URL}"; then
      true
    else
      rc=$?
      if [[ $rc -eq 2 ]]; then downloaded_any=1; else exit $rc; fi
    fi
  fi
fi

ifixit_file="${IFIXIT_ZIM_URL##*/}"
ifixit_path="${ZIM_DIR}/${ifixit_file}"
if [[ -f "${ifixit_path}" ]]; then
  info "iFixit ZIM already present, skipping prompt: ${ifixit_path}"
else
  if prompt_yes_no "Do you want to download the iFixit ZIM?"; then
    if download_zim "${IFIXIT_ZIM_URL}"; then
      true
    else
      rc=$?
      if [[ $rc -eq 2 ]]; then downloaded_any=1; else exit $rc; fi
    fi
  fi
fi

if [[ "${downloaded_any}" -eq 1 ]]; then
  info "New ZIM(s) downloaded; restarting kiwix-serve..."
  start_or_restart_kiwix
fi

info "Installing RaspAP (wireless router software)..."
curl -sL https://install.raspap.com | bash

configure_raspap_ssid

if zim_present && service_is_active; then
  info "Kiwix is running on port ${KIWIX_PORT} (serving ZIMs from ${ZIM_DIR})."
else
  info "Kiwix is not running yet (it requires at least one .zim in ${ZIM_DIR})."
fi

enable_raspap_ap_mode
