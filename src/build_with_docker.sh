#!/bin/bash 

function clean() {
    print_ok "Cleaning up..."
    sudo rm -rf new_building_os || true
    judge "Clean up rootfs"
    sudo rm -rf image || true
    judge "Clean up image"
    sudo rm -f $TARGET_NAME.iso || true
    judge "Clean up iso"
    sudo rm -f $TARGET_NAME-*.tar || true
    judge "Clean up tarballs"
}

function build_base_image() {
    source ./create_base.sh
    setup_host
    judge "set up host"
    create_base_system
    judge "create base image"
}

function build_docker_image() {
    print_ok "building builder   image"
    docker build . -t builder
    judge "create builder image"
    
    print_ok "running docker image"
    docker run -it --name builder \
    --privileged --network=host \
    -v /dev:/dev -v /run:/run -v /proc:/proc  -v /sys:/sys -v /dev/pts:/dev/pts \
    builder /root/mods/run_in_builder.sh
    
    judge "run builder"
    
        print_ok "commiting docker image"
        docker commit builder $TARGET_NAME-all
        judge "commit  image"
}

function export_rootfs() {
    print_ok "exporting container tarball"
    docker export builder -o  $TARGET_NAME-all.tar 
    judge "export tarball"
    
    print_ok "Cleaning up rootfs"
    sudo rm -rf new_building_os || true
    judge "Clean up rootfs"
    
    print_ok "unzipping to rootfs"
    mkdir -p new_building_os 
    sudo tar -xf $TARGET_NAME-all.tar -C new_building_os
    judge "unzip rootfs"
}



# copy from ./build.sh
function build_iso() {
    print_ok "Building ISO image..."

    print_ok "Creating image directory..."
    rm -rf image
    mkdir -p image/{casper,isolinux,.disk}
    judge "Create image directory"

    # copy kernel files
    print_ok "Copying kernel files as /casper/vmlinuz and /casper/initrd..."
    sudo cp new_building_os/boot/vmlinuz-**-**-generic image/casper/vmlinuz
    sudo cp new_building_os/boot/initrd.img-**-**-generic image/casper/initrd
    judge "Copy kernel files"
    
    print_ok "Generating grub.cfg..."
    touch image/$TARGET_NAME
    cp $SCRIPT_DIR/args.sh image/$TARGET_NAME
    judge "Copy build args to disk"

    # Configurations are setup in new_building_os/usr/share/initramfs-tools/scripts/casper-bottom/25configure_init
    TRY_TEXT="Try and Install $TARGET_BUSINESS_NAME"
    cat << EOF > image/isolinux/grub.cfg

search --set=root --file /$TARGET_NAME

insmod all_video

set default="0"
set timeout=10

menuentry "$TRY_TEXT" {
   set gfxpayload=keep
   linux   /casper/vmlinuz boot=casper nopersistent quiet splash ---
   initrd  /casper/initrd
}

menuentry "$TRY_TEXT (Safe Graphics)" {
    set gfxpayload=keep
    linux   /casper/vmlinuz boot=casper nopersistent nomodeset ---
    initrd  /casper/initrd
}

if [ "\$grub_platform" == "efi" ]; then
    menuentry "Boot from next volume" {
        exit 1
    }

    menuentry "UEFI Firmware Settings" {
        fwsetup
    }
fi
EOF
    judge "Generate grub.cfg"


    # generate manifest
    print_ok "Generating manifes for filesystem..."
    sudo chroot new_building_os dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee image/casper/filesystem.manifest >/dev/null 2>&1
    judge "Generate manifest for filesystem"

    print_ok "Generating manifest for filesystem-desktop..."
    sudo cp -v image/casper/filesystem.manifest image/casper/filesystem.manifest-desktop
    for pkg in $TARGET_PACKAGE_REMOVE; do
        sudo sed -i "/$pkg/d" image/casper/filesystem.manifest-desktop
    done
    judge "Generate manifest for filesystem-desktop"

    print_ok "Compressing rootfs as squashfs on /casper/filesystem.squashfs..."
    sudo mksquashfs new_building_os image/casper/filesystem.squashfs \
        -noappend -no-duplicates -no-recovery \
        -wildcards -b 1M \
        -comp zstd -Xcompression-level 19 \
        -e "var/cache/apt/archives/*" \
        -e "root/*" \
        -e "root/.*" \
        -e "tmp/*" \
        -e "tmp/.*" \
        -e "swapfile"
    judge "Compress rootfs"
    
    print_ok "Generating filesystem.size on /casper/filesystem.size..."
    printf $(sudo du -sx --block-size=1 new_building_os | cut -f1) > image/casper/filesystem.size
    judge "Generate filesystem.size"

    print_ok "Generating README.diskdefines..."
    cat << EOF > image/README.diskdefines
#define DISKNAME  Try $TARGET_BUSINESS_NAME
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  amd64
#define ARCHamd64  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF
    judge "Generate README.diskdefines"

    DATE=`TZ="UTC" date +"%y%m%d%H%M"`
    cat << EOF > image/README.md
# $TARGET_BUSINESS_NAME $TARGET_BUILD_VERSION

$TARGET_BUSINESS_NAME is a custom Ubuntu-based Linux distribution that aims to facilitate developers transitioning from Windows to Linux by maintaining familiar operational habits and workflows.

This image is built with the following configurations:

- **Language**: $LANG_MODE
- **Version**: $TARGET_BUILD_VERSION
- **Date**: $DATE

$TARGET_BUSINESS_NAME is distributed with GPLv3 license. You can find the license on [GPL-v3](https://gitlab.aiursoft.cn/anduin/anduinos/-/blob/$TARGET_BUILD_BRANCH/LICENSE).

## Please verify the checksum!!!

To verify the integrity of the image, you can calculate the md5sum of the image and compare it with the value in the file \`md5sum.txt\`.

To do this, run the following command in the terminal:

\`\`\`bash
md5sum -c md5sum.txt | grep -v 'OK'
\`\`\`

No output indicates that the image is correct.

## How to use

Press F12 to enter the boot menu when you start your computer. Select the USB drive to boot from.

## More information

For detailed instructions, please visit [$TARGET_BUSINESS_NAME Document](https://docs.anduinos.com/Install/System-Requirements.html).
EOF

    pushd $SCRIPT_DIR/image
    print_ok "Creating EFI boot image on /isolinux/efiboot.img..."
    (
        cd isolinux && \
        dd if=/dev/zero of=efiboot.img bs=1M count=10 && \
        sudo mkfs.vfat efiboot.img && \
        mkdir efi && \
        sudo mount efiboot.img efi && \
        sudo grub-install --efi-directory=efi --uefi-secure-boot --removable --no-nvram --target=x86_64-efi && \
        sudo umount efi && \
        rm -rf efi
    )
    judge "Create EFI boot image"

    print_ok "Creating BIOS boot image on /isolinux/bios.img..."
    grub-mkstandalone \
        --format=i386-pc \
        --output=isolinux/core.img \
        --install-modules="linux16 linux normal iso9660 biosdisk memdisk search tar ls" \
        --modules="linux16 linux normal iso9660 biosdisk search" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=isolinux/grub.cfg"
    judge "Create BIOS boot image"

    print_ok "Creating hybrid boot image on /isolinux/bios.img..."
    cat /usr/lib/grub/i386-pc/cdboot.img isolinux/core.img > isolinux/bios.img
    judge "Create hybrid boot image"

    print_ok "Creating .disk/info..."
    echo "$TARGET_BUSINESS_NAME $TARGET_BUILD_VERSION $TARGET_UBUNTU_VERSION - Release amd64 ($(date +%Y%m%d))" | sudo tee .disk/info
    judge "Create .disk/info"

    print_ok "Creating md5sum.txt..."
    sudo /bin/bash -c "(find . -type f -print0 | xargs -0 md5sum | grep -v -e 'md5sum.txt' -e 'bios.img' -e 'efiboot.img' > md5sum.txt)"
    judge "Create md5sum.txt"

    print_ok "Creating iso image on $SCRIPT_DIR/$TARGET_NAME.iso..."
    sudo xorriso \
        -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$TARGET_NAME" \
        -eltorito-boot boot/grub/bios.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            --eltorito-catalog boot/grub/boot.cat \
            --grub2-boot-info \
            --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
            -e EFI/efiboot.img \
            -no-emul-boot \
            -append_partition 2 0xef isolinux/efiboot.img \
        -output "$SCRIPT_DIR/$TARGET_NAME.iso" \
        -m "isolinux/efiboot.img" \
        -m "isolinux/bios.img" \
        -graft-points \
            "/EFI/efiboot.img=isolinux/efiboot.img" \
            "/boot/grub/grub.cfg=isolinux/grub.cfg" \
            "/boot/grub/bios.img=isolinux/bios.img" \
            "."

    judge "Create iso image"

    print_ok "Moving iso image to $SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$LANG_MODE-$DATE.iso..."
    mkdir -p $SCRIPT_DIR/dist
    mv $SCRIPT_DIR/$TARGET_NAME.iso $SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$LANG_MODE-$DATE.iso
    judge "Move iso image"

    print_ok "Generating sha256 checksum..."
    HASH=`sha256sum $SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$LANG_MODE-$DATE.iso | cut -d ' ' -f 1`
    echo "SHA256: $HASH" > $SCRIPT_DIR/dist/$TARGET_BUSINESS_NAME-$TARGET_BUILD_VERSION-$LANG_MODE-$DATE.sha256
    judge "Generate sha256 checksum"

    popd
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e                  # exit on error
    set -o pipefail         # exit on pipeline error
    set -u                  # treat unset variable as error
    export SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    source $SCRIPT_DIR/shared.sh
    source $SCRIPT_DIR/args.sh
    clean
    build_base_image
    build_docker_image
    export_rootfs
    build_iso
fi