#!/bin/bash

function create_tarball() {
    sudo tar --numeric-owner -C new_building_os -cf anduinos.tar .
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  create_tarball 
fi