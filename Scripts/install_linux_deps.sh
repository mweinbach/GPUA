#!/usr/bin/env bash
# Swift-only: install Linux dependencies and wgpu-native prebuilt binaries for GPUA
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: this script requires root privileges or sudo." >&2
        exit 1
    fi
else
    SUDO=""
fi

RAW_ARCH="$(uname -m)"
case "${RAW_ARCH}" in
    x86_64|amd64)
        ARCH="x86_64"
        ;;
    aarch64|arm64)
        ARCH="aarch64"
        ;;
    *)
        echo "Unsupported Linux architecture: ${RAW_ARCH}" >&2
        exit 1
        ;;
esac

echo "=== Installing Linux system packages for architecture: ${ARCH} ==="
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
    libwayland-dev \
    wayland-protocols \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libx11-dev \
    libx11-xcb-dev \
    libxcb1-dev \
    libxcb-randr0-dev \
    libxcb-xinput-dev \
    libxcb-sync-dev \
    libxcb-shape0-dev \
    libxcb-xkb-dev \
    libxcursor-dev \
    libxi-dev \
    libxrandr-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libfontconfig1-dev \
    fonts-dejavu-core \
    xvfb \
    mesa-vulkan-drivers \
    libvulkan1 \
    curl \
    unzip

echo "=== Symlinking FreeType headers into /usr/local/include ==="
$SUDO mkdir -p /usr/local/include
if [ -e /usr/include/freetype2/ft2build.h ]; then
    $SUDO ln -sf /usr/include/freetype2/ft2build.h /usr/local/include/ft2build.h
fi
if [ -d /usr/include/freetype2/freetype ]; then
    $SUDO rm -rf /usr/local/include/freetype
    $SUDO ln -sf /usr/include/freetype2/freetype /usr/local/include/freetype
fi

WGPU_VERSION="v24.0.0.2"
TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "=== Downloading wgpu-native ${WGPU_VERSION} for Linux (${ARCH}) ==="
WGPU_URL="https://github.com/gfx-rs/wgpu-native/releases/download/${WGPU_VERSION}/wgpu-linux-${ARCH}-release.zip"
curl -fsSL "${WGPU_URL}" -o "${TMP_DIR}/wgpu.zip"

echo "=== Extracting libwgpu_native.so to /usr/local/lib/ ==="
$SUDO mkdir -p /usr/local/lib
$SUDO unzip -q -o -j "${TMP_DIR}/wgpu.zip" "lib/libwgpu_native.so" -d /usr/local/lib/
$SUDO cp -f /usr/local/lib/libwgpu_native.so /usr/lib/ 2>/dev/null || true

echo "=== Running ldconfig ==="
$SUDO ldconfig

LVP_ICD="$(ls /usr/share/vulkan/icd.d/lvp_icd*.json 2>/dev/null | head -n1 || true)"
if [ -n "${LVP_ICD}" ]; then
    echo "=== Configuring Vulkan ICD discovery for Lavapipe (${LVP_ICD}) ==="
    $SUDO mkdir -p /etc/profile.d
    echo "export VK_ICD_FILENAMES=\"${LVP_ICD}\"" | $SUDO tee /etc/profile.d/gpua_vulkan.sh >/dev/null
    if [ -f /etc/environment ]; then
        if ! grep -q "VK_ICD_FILENAMES" /etc/environment 2>/dev/null; then
            echo "VK_ICD_FILENAMES=\"${LVP_ICD}\"" | $SUDO tee -a /etc/environment >/dev/null
        fi
    fi
    echo "Lavapipe Vulkan ICD discovered and configured: ${LVP_ICD}"
else
    echo "Warning: No lvp_icd*.json found under /usr/share/vulkan/icd.d/" >&2
fi

echo "=== Linux dependencies and wgpu-native ${WGPU_VERSION} successfully installed! ==="
