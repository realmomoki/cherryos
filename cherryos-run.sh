#!/usr/bin/env bash
# cherryos-run.sh - Launcher cherryOS (https://cherryos.dev) untuk Linux
#
# Catatan: cherryOS berjalan DI DALAM browser, jadi skrip ini hanya:
#   1. Mencari browser Chromium/Chrome yang terpasang
#   2. Membukanya dengan profil terpisah + flag GPU/WebGPU
#   3. (Opsional) Memantau suhu GPU NVIDIA dan menutup browser jika terlalu panas
#
# Pakai:  chmod +x cherryos-run.sh && ./cherryos-run.sh
# Opsi:   MAX_TEMP=80 ./cherryos-run.sh      (batas suhu Celsius, default 83)
#         PROFILE_DIR=~/x ./cherryos-run.sh  (lokasi profil browser)

set -euo pipefail

URL="https://cherryos.dev/"
PROFILE_DIR="${PROFILE_DIR:-$HOME/.cherryos-profile}"
MAX_TEMP="${MAX_TEMP:-83}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"

log() { printf '[cherryos] %s\n' "$*"; }

# --- 1. Cari browser -------------------------------------------------------
BROWSER=""
for b in google-chrome-stable google-chrome chromium chromium-browser brave-browser microsoft-edge; do
  if command -v "$b" >/dev/null 2>&1; then
    BROWSER="$b"
    break
  fi
done

if [[ -z "$BROWSER" ]]; then
  log "Browser Chromium/Chrome tidak ditemukan."
  log "Install dulu, contoh Debian/Ubuntu: sudo apt install chromium"
  log "Atau Fedora: sudo dnf install chromium | Arch: sudo pacman -S chromium"
  exit 1
fi
log "Browser: $BROWSER"

# --- 2. Cek GPU ------------------------------------------------------------
HAS_NVIDIA=0
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  HAS_NVIDIA=1
  log "GPU NVIDIA terdeteksi: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"
else
  log "nvidia-smi tidak tersedia/tidak berfungsi."
  log "Kalau pakai AMD/Intel, pastikan driver Mesa + Vulkan terpasang (cek: vulkaninfo --summary)."
  log "Pemantau suhu otomatis dinonaktifkan."
fi

if ! command -v vulkaninfo >/dev/null 2>&1; then
  log "Peringatan: vulkaninfo tidak ada (paket vulkan-tools). WebGPU di Linux butuh Vulkan."
fi

# --- 3. Jalankan browser ---------------------------------------------------
mkdir -p "$PROFILE_DIR"

FLAGS=(
  "--user-data-dir=$PROFILE_DIR"
  "--no-first-run"
  "--no-default-browser-check"
  # WebGPU / akselerasi GPU di Linux
  "--enable-unsafe-webgpu"
  "--enable-features=Vulkan,VaapiVideoDecoder"
  "--use-angle=vulkan"
  "--ignore-gpu-blocklist"
  "--enable-gpu-rasterization"
  "--enable-zero-copy"
  # Jangan di-throttle saat tab di background
  "--disable-background-timer-throttling"
  "--disable-renderer-backgrounding"
  "--disable-backgrounding-occluded-windows"
)

log "Membuka $URL ..."
"$BROWSER" "${FLAGS[@]}" "$URL" >/dev/null 2>&1 &
BROWSER_PID=$!

cleanup() {
  log "Menutup browser..."
  kill "$BROWSER_PID" 2>/dev/null || true
}
trap cleanup INT TERM

# --- 4. Pemantau suhu (NVIDIA) --------------------------------------------
if [[ "$HAS_NVIDIA" -eq 1 ]]; then
  log "Pemantau suhu aktif (batas ${MAX_TEMP}C, cek tiap ${CHECK_INTERVAL}s). Ctrl+C untuk berhenti."
  while kill -0 "$BROWSER_PID" 2>/dev/null; do
    TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | sort -nr | head -n1 | tr -d ' ')
    UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1 | tr -d ' ')
    log "Suhu GPU: ${TEMP}C | Beban: ${UTIL}%"
    if [[ "${TEMP:-0}" -ge "$MAX_TEMP" ]]; then
      log "SUHU TERLALU TINGGI (${TEMP}C >= ${MAX_TEMP}C). Browser ditutup demi keamanan GPU."
      cleanup
      exit 2
    fi
    sleep "$CHECK_INTERVAL"
  done
else
  log "Browser berjalan. Tekan Ctrl+C untuk keluar."
  wait "$BROWSER_PID"
fi

log "Selesai."
