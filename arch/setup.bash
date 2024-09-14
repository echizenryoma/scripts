#!/bin/bash

INSTALL_ROOT="/install"
MOUNT_ROOT="/mnt"

source /install/.env

arch_chroot_exec() {
    arch-chroot "${MOUNT_ROOT}" bash -c "$*"
}

gen_systemd_network_config() {
    local interface="$1"
    local dhcp="$2"
    local ipv4_address="$3"
    local ipv4_gateway="$4"
    local ipv6_address="$5"
    local ipv6_gateway="$6"

    local config="[Match]\nName=${interface}\n\n[Network]\n"

    if [[ "$dhcp" == "Y" ]]; then
        config+="DHCP=both\nDNS=1.1.1.1\nDNS=8.8.8.8\n\n[DHCP]\nUseDNS=false\n"
    else
        if [[ -n $ipv4_address ]]; then
            config+="Address=${ipv4_address}\nDNS=1.1.1.1\nDNS=8.8.8.8\n"
        fi
        if [[ -n $ipv6_address ]]; then
            config+="Address=${ipv6_address}\nDNS=2606:4700:4700::1111\nIPv6AcceptRA=0\n"
        fi
        if [[ -n $ipv4_gateway ]]; then
            config+="\n[Route]\nGateway=${ipv4_gateway}\nGatewayOnLink=yes\n"
        fi
        if [[ -n $ipv6_gateway ]]; then
            config+="\n[Route]\nGateway=${ipv6_gateway}\nGatewayOnLink=yes\n"
        fi
    fi
    echo -e $config
}

mount_fs() {
    mount ${ROOT_DEV} "${MOUNT_ROOT}"
    chattr -R -ia "${MOUNT_ROOT}" >/dev/null 2>&1
    if [[ ${IS_UEFI} == "Y" ]]; then
        mkdir -p "${MOUNT_ROOT}/efi"
        mount $EFI_DEV "${MOUNT_ROOT}/efi"
        chattr -R -ia "${MOUNT_ROOT}/efi" >/dev/null 2>&1
    fi

    if [[ -n "${BOOT_DEV}" ]]; then
        mkdir -p "${MOUNT_ROOT}/boot"
        mount ${BOOT_DEV} "${MOUNT_ROOT}/boot"
        chattr -R -ia "${MOUNT_ROOT}/boot" >/dev/null 2>&1
    fi
}

configure_network() {
    if [[ "${IPV4_INTERFACE}" == "${IPV6_INTERFACE}" || -z "${IPV6_INTERFACE}" ]]; then
        cat <<EOF >${MOUNT_ROOT}/etc/systemd/network/00-wan0.link
[Match]
MACAddress=${IPV4_INTERFACE_MAC}

[Link]
Name=wan0
EOF
        gen_systemd_network_config "wan0" "${IS_DHCP}" "${IPV4_ADDRESS}" "${IPV4_GATEWAY}" "${IPV6_ADDRESS}" "${IPV6_GATEWAY}" >${MOUNT_ROOT}/etc/systemd/network/00-wan0.network
    else

        cat <<EOF >${MOUNT_ROOT}/etc/systemd/network/00-wan0.link
[Match]
MACAddress=${IPV4_INTERFACE_MAC}

[Link]
Name=wan0
EOF
        gen_systemd_network_config "wan0" "${IS_DHCP}" "${IPV4_ADDRESS}" "${IPV4_GATEWAY}" "" "" >${MOUNT_ROOT}/etc/systemd/network/00-wan0.network
        cat <<EOF >${MOUNT_ROOT}/etc/systemd/network/01-wan1.link
[Match]
MACAddress=${IPV6_INTERFACE_MAC}

[Link]
Name=wan1
EOF
        gen_systemd_network_config "wan1" "${IS_DHCP}" "" "" "${IPV6_ADDRESS}" "${IPV6_GATEWAY}" >${MOUNT_ROOT}/etc/systemd/network/01-wan1.network
    fi
}

backup_config() {
    cp -Lf ${MOUNT_ROOT}/etc/fstab /etc/fstab
}

delete_all() {
    pushd "${MOUNT_ROOT}"
    rm -rf bin boot etc home opt root sbin srv usr var vml* ini* lib* med* snap* *.tar.gz
    popd
}

install_arch() {
    curl -Ls "https://archlinux.org/mirrorlist/?country=${LOC}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" | sed 's|#Server|Server|g' >/etc/pacman.d/mirrorlist
    echo 'Server = https://cloudflaremirrors.com/archlinux/$repo/os/$arch' >>/etc/pacman.d/mirrorlist
    pacman-key --init
    pacman-key --populate
    sed -i 's|#Color|Color|' /etc/pacman.conf
    sed -i 's|#ParallelDownloads|ParallelDownloads|' /etc/pacman.conf
    pacstrap /mnt base linux-lts nano openssh grub intel-ucode amd-ucode sudo firewalld xfsprogs
    if [[ $IS_UEFI == "Y" ]]; then
        pacstrap /mnt efibootmgr
    fi
    if [[ $IS_HYPERV == "Y" ]]; then
        pacstrap /mnt hyperv
    fi
}

configure_arch() {
    cp -f /etc/fstab ${MOUNT_ROOT}/etc/fstab
    cp -Lf /etc/resolv.conf ${MOUNT_ROOT}/etc/resolv.conf
    cp -f /etc/systemd/network/* ${MOUNT_ROOT}/etc/systemd/network
    sed -i 's|/boot/efi|/efi|' ${MOUNT_ROOT}/etc/fstab
    cp -f /etc/pacman.d/mirrorlist ${MOUNT_ROOT}/etc/pacman.d/mirrorlist
    cp -f /etc/fstab ${MOUNT_ROOT}/etc/fstab

    cat <<EOF >${MOUNT_ROOT}/etc/sysctl.d/70-bbr.conf
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr
EOF
    arch_chroot_exec systemctl enable systemd-networkd
    arch_chroot_exec systemctl enable systemd-resolved

    if [[ $IS_HYPERV == "Y" ]]; then
        arch_chroot_exec sed -i "s|^MODULES=(.*)|MODULES=(hv_storvsc hv_vmbus)|g" /etc/mkinitcpio.conf
    fi
    arch_chroot_exec sed -i "s|PRESETS=(.*)|PRESETS=('default')|g" /mnt/etc/mkinitcpio.d/linux-lts.preset
    arch_chroot_exec sed -i "s|^HOOKS=(.*)|HOOKS=(base systemd autodetect microcode modconf kms keyboard block filesystems fsck)|g" /etc/mkinitcpio.conf
    arch_chroot_exec sed -i 's|#Color|Color|' /etc/pacman.conf
    arch_chroot_exec sed -i 's|#ParallelDownloads|ParallelDownloads|' /etc/pacman.conf
    arch_chroot_exec sed -i 's|# include \"/usr/share/nano/\*\.nanorc\"|include "/usr/share/nano/*.nanorc"|' /etc/nanorc
    arch_chroot_exec mkinitcpio -P
    arch_chroot_exec rm -f /boot/initramfs-linux-lts-fallback.img
}

configure_sshd() {
    cat <<'EOF' >${MOUNT_ROOT}/etc/ssh/sshd_config.d/00-init
PasswordAuthentication no
PermitRootLogin prohibit-password
EOF
    mkdir -p ${MOUNT_ROOT}/root/.ssh
    cp -f /root/.ssh/authorized_keys ${MOUNT_ROOT}/root/.ssh/authorized_keys
    chmod 755 ${MOUNT_ROOT}/root/.ssh
    chmod 644 ${MOUNT_ROOT}/root/.ssh/authorized_keys

    arch_chroot_exec systemctl enable sshd
    arch_chroot_exec sed -i "/Port 22$/a\Port 10022" /etc/ssh/sshd_config
    arch_chroot_exec firewall-offline-cmd --add-port=10022/tcp
    arch_chroot_exec systemctl enable firewalld
}

configure_bootloader() {
    arch_chroot_exec sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"|g' /mnt/etc/default/grub
    arch_chroot_exec echo 'GRUB_SERIAL_COMMAND="serial --speed=115200"' >>/etc/default/grub
    arch_chroot_exec echo 'GRUB_EARLY_INITRD_LINUX_STOCK=""' >>/etc/default/grub
    if [[ $IS_UEFI == "Y" ]]; then
        arch_chroot_exec grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=arch
        arch_chroot_exec grub-mkconfig -o /boot/grub/grub.cfg
        arch_chroot_exec mkdir -p /efi/EFI/BOOT
        arch_chroot_exec cp -f /efi/EFI/arch/grubx64.efi /efi/EFI/BOOT/BOOTX64.EFI
    else
        if [[ -n "${BOOT_DEV}" ]]; then
            arch_chroot_exec grub-install --target=i386-pc --boot-directory=/boot ${ROOT_DISK} --force
        else
            arch_chroot_exec grub-install --target=i386-pc ${ROOT_DISK} --force
        fi
        arch_chroot_exec grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

write_disk() {
    arch_chroot_exec sync
}

set_root_password() {
    arch_chroot_exec echo "Set root Password:"
    arch_chroot_exec passwd
}

mount_fs
backup_config
delete_all
install_arch
configure_arch
configure_network
configure_sshd
configure_bootloader
write_disk
set_root_password
