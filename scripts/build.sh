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
    git config --global url."https://github.com/FFmpeg/FFmpeg.git".insteadOf "https://git.ffmpeg.org/ffmpeg.git"
}

build_package() {
    cd "$WORK_DIR"
    local pkg_dir="$1"
    if [ ! -d "$pkg_dir" ]; then
        log "Local folder not found. Cloning from AUR: $pkg_dir"
        if ! git clone "https://aur.archlinux.org/$pkg_dir.git"; then
            echo "ERROR: Failed to clone $pkg_dir"
            exit 1
        fi
        chown -R builder:builder "$pkg_dir"
    fi
    if [ ! -d "$WORK_DIR/$pkg_dir" ]; then
        error "Directory $pkg_dir not found!"
    fi
    cd "$WORK_DIR/$pkg_dir"
    log "Patching arch to aarch64..."
    sed -i "s/^arch=(.*)/arch=('aarch64')/" PKGBUILD
    log "Building: $pkg_dir"
    rm -f *.pkg.tar.*
    sudo -u builder makepkg -s --noconfirm --needed --skippgpcheck
    PKG_FILES=$(find . -maxdepth 1 -type f -name "*.pkg.tar.*" ! -name "*.sig")
    if [ -n "$PKG_FILES" ]; then
        for f in $PKG_FILES; do
            PKG_BASE=$(basename "$f")
            success "Package built: $PKG_BASE"
            cp -v "$f" "$OUTPUT_DIR/$PKG_BASE"
            if [[ "$pkg_dir" == *"linux-"* ]]; then
                log "Skipping installation for Kernel package..."
            else
                log "Installing $PKG_BASE to system..."
                pacman -U --noconfirm "$f"
            fi
        done
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
    "linux-collabora-rockchip-devel"
)

for pkg in "${PACKAGES[@]}"; do
    build_package "$pkg"
done

log "Zipping all packages..."
cd "$OUTPUT_DIR"
zip -r packages.zip ./*
log "All builds finished. Artifacts are in $OUTPUT_DIR"
chmod -R 777 "$OUTPUT_DIR"
