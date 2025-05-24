#!/bin/bash

function run_builder() {
    /usr/bin/env DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-readline} \
    /root/mods/install_all_mods.sh -
    judge "Install all mods"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e                  # exit on error
    set -o pipefail         # exit on pipeline error
    set -u                  # treat unset variable as error
    export SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    source $SCRIPT_DIR/shared.sh
    source $SCRIPT_DIR/args.sh
    run_builder
fi
