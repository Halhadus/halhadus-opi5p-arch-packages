#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

WORK_DIR="/workspace"
OUTPUT_DIR="/output"

log() { echo -e "${BLUE}:: $1${NC}"; }
success() { echo -e "${GREEN}[OK] $1${NC}"; }
error() { echo -e "${RED}[FAIL] $1${NC}"; exit 1; }

prepare_env() {
    log "Environment Preparation..."
    pacman-key --init
    pacman-key --populate archlinuxarm
    pacman -Syu --noconfirm --needed \
        base-devel git cmake curl zip sudo \
        mesa libglvnd pipewire-jack wayland-protocols \
        cairo glibmm iio-sensor-proxy librsvg libdisplay-info
    useradd -m builder
    echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
    chown -R builder:builder "$WORK_DIR"
    chown -R builder:builder "$OUTPUT_DIR"
    sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j4"/' /etc/makepkg.conf
}

build_package() {
    local pkg_dir="$1"
    if [ ! -d "$pkg_name" ]; then
        log "Local folder not found. Cloning from AUR: $pkg_name"
        sudo -u builder git clone "https://aur.archlinux.org/$pkg_name.git"
    fi
    if [ ! -d "$WORK_DIR/$pkg_dir" ]; then
        error "Directory $pkg_dir not found!"
    fi
    log "Patching arch to aarch64..."
    sed -i "s/^arch=(.*)/arch=('aarch64')/" PKGBUILD
    log "Building: $pkg_dir"
    cd "$WORK_DIR/$pkg_dir"
    rm -f *.pkg.tar.*
    sudo -u builder makepkg -s --noconfirm --needed --skippgpcheck
    PKG_FILE=$(find . -maxdepth 1 -type f -name "*.pkg.tar.*" ! -name "*.sig" | head -n 1)
    if [ -n "$PKG_FILE" ]; then
        PKG_FILE=$(basename "$PKG_FILE")
        success "$pkg_dir built successfully."
        log "Installing $PKG_FILE to system..."
        cp -v "$PKG_FILE" "$OUTPUT_DIR/"
        pacman -U --noconfirm "$PKG_FILE"
        repo-add "$OUTPUT_DIR/halhadus-repo.db.tar.gz" "$OUTPUT_DIR/$PKG_FILE"
    else
        error "No package file created for $pkg_dir"
    fi
}

prepare_env

PACKAGES=(
    "ffmpeg-v4l2-request"
    "mpv-v4l2-request"
    "wf-config"
    "wayfire"
    "wayfire-plugins-extra"
    "glfw-wayland-minecraft-cursorfix"
    "mangohud-aarch64"
    "nvtop-panthor"
    "wlrctl"
)

for pkg in "${PACKAGES[@]}"; do
    build_package "$pkg"
done

log "All builds finished. Artifacts are in $OUTPUT_DIR"
chmod -R 777 "$OUTPUT_DIR"
