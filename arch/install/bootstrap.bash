#!/bin/bash

get_mount_fs() {
    local root=$1
    df ${root} | sed '1d' | awk '{print $1}'
}

LOC=$(get_loc)
echo "LOC: ${LOC}"

IS_UEFI=$(is_uefi)
echo "UEFI: ${IS_UEFI}"

read -p "Enable DHCP?(1/NULL): " IS_DHCP
read -p "Is Hyper-V?(1/NULL): " IS_HYPERV

ROOT_DEV=$(get_mount_fs /)
if [[ $IS_UEFI == "1" ]]; then
    EFI_DEV=$(get_mount_fs /boot/efi)
fi

mkdir -p /tmp/5c44cf21-1004-4f76-8ee6-aec3f527aa0a
cat << EOF > /tmp/5c44cf21-1004-4f76-8ee6-aec3f527aa0a/.env
IS_UEFI=${IS_UEFI}
ROOT_DEV=${ROOT_DEV}
EFI_DEV=${EFI_DEV}
LOC=${LOC}
IS_DHCP=${IS_DHCP}
IS_HYPERV=${IS_HYPERV}
EOF
curl -Ls "https://github.com/echizenryoma/scripts/raw/main/arch/install/setup.bash" -o /tmp/5c44cf21-1004-4f76-8ee6-aec3f527aa0a/setup.bash

ARCHLINUX_BOOTSTRAP_URL=$(curl -Ls "https://archlinux.org/mirrorlist/?country=${LOC}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" | grep "Server" | sed 's|$repo/os/$arch|iso/latest/archlinux-bootstrap-x86_64.tar.gz|g' | awk '{print $3}' | head -n 1)
curl -L "${ARCHLINUX_BOOTSTRAP_URL}" -O /archlinux-bootstrap-x86_64.tar.gz
mkdir /install
cd /install
tar xzf /archlinux-bootstrap-x86_64.tar.gz --numeric-owner
echo "Server = https://${ArchMirrorDomain}/archlinux/\$repo/os/\$arch" >> /install/root.x86_64/etc/pacman.d/mirrorlist
/install/root.x86_64/bin/arch-chroot /install/root.x86_64/ /tmp/5c44cf21-1004-4f76-8ee6-aec3f527aa0a/setup.bash
