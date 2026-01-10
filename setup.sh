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
User=kiwix
ExecStart=/usr/bin/bash -c "/usr/bin/kiwix-serve -p 8080 /srv/kiwix/content/*.zim"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kiwix-serve >/dev/null

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

start_or_restart_kiwix

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

info "Done."
if zim_present && service_is_active; then
  info "Kiwix is running on port ${KIWIX_PORT} (serving ZIMs from ${ZIM_DIR})."
else
  info "Kiwix is not running yet (it requires at least one .zim in ${ZIM_DIR})."
fi
