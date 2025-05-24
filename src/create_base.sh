#!/bin/bash

# modify   from ./build.sh
function setup_host() {
    print_ok "Setting up host environment..."
    sudo apt update
    sudo apt install -y \
        binutils \
        debootstrap \
        squashfs-tools \
        xorriso \
        grub-pc-bin \
        grub-efi-amd64 \
        grub2-common \
        mtools \
        dosfstools \
        docker.io \
        --no-install-recommends
    judge "Install required tools"
    
    print_ok "Cleaning up rootfs"
    sudo rm -rf new_building_os || true
    judge "Clean up rootfs"

    print_ok "Creating new_building_os directory..."
    sudo mkdir -p new_building_os
    judge "Create new_building_os directory"

    print_ok "Setting up mods executable..."
    find . -type f -name "*.sh" -exec chmod +x {} \;
    judge "Set up mods executable"
}

function create_base_system() {
    print_ok "Calling debootstrap to download base debian system..."
    sudo debootstrap  --arch=amd64 --variant=minbase $TARGET_UBUNTU_VERSION new_building_os $BUILD_UBUNTU_MIRROR
    judge "Download base system"
    print_ok "createing base tarball ..."
    sudo tar --numeric-owner  -C new_building_os -cf debootstrap.tar .
    judge "create base tarball"
    print_ok "importing base system to docker ..."
    docker import debootstrap.tar base 
    judge "import base system"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e                  # exit on error
    set -o pipefail         # exit on pipeline error
    set -u                  # treat unset variable as error
    export SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    source $SCRIPT_DIR/shared.sh
    source $SCRIPT_DIR/args.sh
    setup_host
    create_base_system
fi