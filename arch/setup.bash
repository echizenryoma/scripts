#!/bin/bash

INSTALL_ROOT="/install"
MOUNT_ROOT="/mnt"

source "${INSTALL_ROOT}/.env"

arch_chroot_exec() {
    arch-chroot "${MOUNT_ROOT}" $*
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
        config+="DHCP=both\n"
    else
        if [[ -n $ipv4_address ]]; then
            config+="Address=${ipv4_address}\n"
        fi
        if [[ -n $ipv6_address ]]; then
            config+="Address=${ipv6_address}\nIPv6AcceptRA=0\n"
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

gen_resolv_config() {
    loc config=""
    if [[ "$LOC" == "CN" ]]; then
        if [[ -n "${IPV4_ADDRESS}" ]]; then
            config+="nameserver 119.29.29.29\n"
            config+="nameserver 223.6.6.6\n"
        fi
        if [[ -n "${IPV6_ADDRESS}" ]]; then
            config+="nameserver 2400:3200:baba::1\n"
        fi
    else
        if [[ -n "${IPV4_ADDRESS}" ]]; then
            config+="nameserver 1.1.1.1\n"
            config+="nameserver 8.8.8.8\n"
        fi
        if [[ -n "${IPV6_ADDRESS}" ]]; then
            config+="nameserver 2606:4700:4700::1111\n"
        fi
    fi
    config+="search .\n"
    echo -e "$config"
}

mount_fs() {
    mount ${ROOT_DEV} "${MOUNT_ROOT}"
    if [[ ${IS_UEFI} == "Y" ]]; then
        mkdir -p "${MOUNT_ROOT}/efi"
        mount $EFI_DEV "${MOUNT_ROOT}/efi"
    fi

    if [[ -n "${BOOT_DEV}" ]]; then
        mkdir -p "${MOUNT_ROOT}/boot"
        mount ${BOOT_DEV} "${MOUNT_ROOT}/boot"
    fi
}

umount_fs() {
    if [[ ${IS_UEFI} == "Y" ]]; then
        umount $EFI_DEV
    fi

    if [[ -n "${BOOT_DEV}" ]]; then
        umount ${BOOT_DEV}
    fi
    umount ${ROOT_DEV}
}

configure_network() {
    if [[ -z "${IPV4_INTERFACE}"  ]]; then
        cat <<EOF >${MOUNT_ROOT}/etc/systemd/network/00-wan0.link
[Match]
MACAddress=${IPV6_INTERFACE_MAC}

[Link]
Name=wan0
EOF
        gen_systemd_network_config "wan0" "${IS_DHCP}" "" "" "${IPV6_ADDRESS}" "${IPV6_GATEWAY}" >${MOUNT_ROOT}/etc/systemd/network/00-wan0.network
    elif [[ "${IPV4_INTERFACE}" == "${IPV6_INTERFACE}" || -z "${IPV6_INTERFACE}" ]]; then
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
    find ${MOUNT_ROOT} -mindepth 1 -maxdepth 1 \( \
        ! -path "${MOUNT_ROOT}/dev" -and \
        ! -path "${MOUNT_ROOT}/proc" -and \
        ! -path "${MOUNT_ROOT}/sys" -and \
        ! -path "${MOUNT_ROOT}/selinux" -and \
        ! -path "${MOUNT_ROOT}${INSTALL_ROOT}" \
        \) -exec chattr -iRa {} + 2>/dev/null || true

    find ${MOUNT_ROOT} -mindepth 1 -maxdepth 1 \( \
        ! -path "${MOUNT_ROOT}/dev" -and \
        ! -path "${MOUNT_ROOT}/proc" -and \
        ! -path "${MOUNT_ROOT}/sys" -and \
        ! -path "${MOUNT_ROOT}/selinux" -and \
        ! -path "${MOUNT_ROOT}${INSTALL_ROOT}" \
        \) -exec rm -rf {} + 2>/dev/null || true
}

install_arch() {
    curl -Ls "https://archlinux.org/mirrorlist/?country=${LOC}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" | sed 's|#Server|Server|g' | grep Server | shuf | head -n 5 >/etc/pacman.d/mirrorlist
    echo 'Server = https://cloudflaremirrors.com/archlinux/$repo/os/$arch' >>/etc/pacman.d/mirrorlist
    pacman-key --init
    pacman-key --populate
    sed -i 's|#Color|Color|' /etc/pacman.conf
    sed -i 's|#ParallelDownloads|ParallelDownloads|' /etc/pacman.conf

    local base_packages="base linux-lts"
    if [[ ${CPU_VENDOR} == "Intel" ]]; then
        base_packages="${base_packages} intel-ucode"
    elif [[ ${CPU_VENDOR} == "AMD" ]]; then
        base_packages="${base_packages} amd-ucode"
    fi
    local extra_packages="nano grub openssh sudo firewalld git"
    if [[ $ROOT_FS == "xfs" || $ROOT_FS == "xfs" ]]; then
        extra_packages="${extra_packages} xfsprogs"
    fi
    if [[ $IS_UEFI == "Y" ]]; then
        extra_packages="${extra_packages} efibootmgr"
    fi
    if [[ $IS_HYPERV == "Y" ]]; then
        extra_packages="${extra_packages} hyperv"
    fi
    pacstrap ${MOUNT_ROOT} ${base_packages} ${extra_packages}
}

configure_arch() {
    umount /etc/resolv.conf
    gen_resolv_config >${MOUNT_ROOT}/etc/resolv.conf

    cp -f /etc/fstab ${MOUNT_ROOT}/etc/fstab
    sed -i 's|/boot/efi|/efi|' ${MOUNT_ROOT}/etc/fstab
    cp -f /etc/pacman.d/mirrorlist ${MOUNT_ROOT}/etc/pacman.d/mirrorlist

    cat <<EOF >${MOUNT_ROOT}/etc/sysctl.d/70-bbr.conf
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr
EOF
    arch_chroot_exec systemctl enable systemd-networkd

    if [[ $IS_HYPERV == "Y" ]]; then
        sed -i "s|^MODULES=(.*)|MODULES=(hv_storvsc hv_vmbus)|g" ${MOUNT_ROOT}/etc/mkinitcpio.conf
    fi
    sed -i "s|PRESETS=(.*)|PRESETS=('default')|g" ${MOUNT_ROOT}/etc/mkinitcpio.d/linux-lts.preset
    sed -i "s|^HOOKS=(.*)|HOOKS=(base systemd autodetect microcode modconf kms keyboard block filesystems fsck)|g" ${MOUNT_ROOT}/etc/mkinitcpio.conf
    sed -i 's|#Color|Color|' ${MOUNT_ROOT}/etc/pacman.conf
    sed -i 's|#ParallelDownloads|ParallelDownloads|' ${MOUNT_ROOT}/etc/pacman.conf
    sed -i 's|# include \"/usr/share/nano/\*\.nanorc\"|include "/usr/share/nano/*.nanorc"|' ${MOUNT_ROOT}/etc/nanorc
    arch_chroot_exec mkinitcpio -P
    arch_chroot_exec rm -f /boot/initramfs-linux-lts-fallback.img
}

configure_sshd() {
    cat <<'EOF' >${MOUNT_ROOT}/etc/ssh/sshd_config.d/00-cloud.conf
Port 10022
PasswordAuthentication no
PermitRootLogin prohibit-password
EOF
    mkdir -p ${MOUNT_ROOT}/root/.ssh
    cp -f /root/.ssh/authorized_keys ${MOUNT_ROOT}/root/.ssh/authorized_keys
    chmod 755 ${MOUNT_ROOT}/root/.ssh
    chmod 644 ${MOUNT_ROOT}/root/.ssh/authorized_keys

    arch_chroot_exec systemctl enable sshd
    arch_chroot_exec firewall-offline-cmd --add-port=10022/tcp
    arch_chroot_exec systemctl enable firewalld
}

configure_bootloader() {
    sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"|g' ${MOUNT_ROOT}/etc/default/grub
    echo 'GRUB_SERIAL_COMMAND="serial --speed=115200"' >>${MOUNT_ROOT}/etc/default/grub
    echo 'GRUB_EARLY_INITRD_LINUX_STOCK=""' >>${MOUNT_ROOT}/etc/default/grub
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
    echo "${ROOT_PASS}" | arch_chroot_exec passwd --stdin root
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
umount_fs
