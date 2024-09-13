#!/bin/bash

INSTALL_ROOT="/install"
MOUNT_ROOT="/mnt"

bootstrap_chroot_exec() {
    ${INSTALL_ROOT}/root.x86_64/bin/arch-chroot "${INSTALL_ROOT}/root.x86_64/" bash -c "$*"
}

arch_chroot_exec() {
    ${INSTALL_ROOT}/root.x86_64/bin/arch-chroot "${MOUNT_ROOT}" bash -c "$*"
}

get_mount_fs() {
    local root=$1
    df ${root} | sed '1d' | awk '{print $1}'
}

is_uefi() {
    if [ -d "/sys/firmware/efi" ]; then
        echo "Y"
    else
        echo "N"
    fi
}

get_ipv4_default_if() {
    ip route | awk '/default/ {print $5}' | head -n 1
}

get_ipv6_default_if() {
    ip -6 route | awk '/default/ {print $5}' | head -n 1
}

get_default_ipv4() {
    local interface=$(get_ipv4_default_if)
    ip -o -4 addr show dev "$interface" | awk '{print $4}' | head -n 1
}

get_default_ipv6() {
    local interface=$(get_ipv6_default_if)
    ip -o -6 addr show dev "$interface" | awk '{print $4}' | head -n 1
}

get_default_ipv4_gateway() {
    local interface=$(get_ipv4_default_if)
    ip route show dev "$interface" | awk '/default/{print $3}' | head -n 1
}

get_default_ipv6_gateway() {
    local interface=$(get_ipv6_default_if)
    ip -6 route show dev "$interface" | awk '/default/{print $3}' | head -n 1
}

get_if_mac() {
    local interface=$1
    ip link show "$interface" | awk '/link\/ether/{print $2}'
}

get_disk() {
    local partition="$1"
    if [[ $partition == nvme* ]]; then
        disk=$(echo $partition | sed 's/p[0-9]*$//')
    else
        disk=$(echo $partition | sed 's/[0-9]*$//')
    fi
    echo $disk
}

read_yes_or_no() {
    local input=""
    read input
    input="${input:0:1}"
    input=$(echo "$input" | tr '[:lower:]' '[:upper:]')
    if [[ "$input" != "Y" ]]; then
        input="N"
    fi
    echo $input
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

install_dependencies() {
    apt update && apt install -y coreutils gawk curl tar zstd
}

get_configure() {
    LOC=$(curl --connect-timeout 3 -Ls "myip.rdbg.net/loc")

    IPV4_INTERFACE=$(get_ipv4_default_if)
    IPV6_INTERFACE=$(get_ipv6_default_if)
    IPV4_INTERFACE_MAC=$(get_if_mac ${IPV4_INTERFACE})
    IPV6_INTERFACE_MAC=$(get_if_mac ${IPV6_INTERFACE})
    IPV4_ADDRESS=$(get_default_ipv4)
    IPV4_GATEWAY=$(get_default_ipv4_gateway)
    IPV6_ADDRESS=$(get_default_ipv6)
    IPV6_GATEWAY=$(get_default_ipv6_gateway)

    IS_UEFI=$(is_uefi)
    echo "UEFI: ${IS_UEFI}"

    read -p "SSH_KEY_PATH([/root/.ssh/authorized_keys]):" SSH_KEY_PATH
    if [[ -z "SSH_KEY_PATH" ]]; then
        SSH_KEY_PATH=/root/.ssh/authorized_keys
    fi

    echo -n "Enable DHCP?(Y/[N]): "
    IS_DHCP=$(read_yes_or_no)
    echo -n "Is Hyper-V?(Y/[N]): "
    IS_HYPERV=$(read_yes_or_no)

    ROOT_DEV=$(get_mount_fs /)
    ROOT_DISK=$(get_disk ${ROOT_DEV})
    if [[ $IS_UEFI == "Y" ]]; then
        EFI_DEV=$(get_mount_fs /boot/efi)
    fi
    BOOT_DEV=$(get_mount_fs /boot)
    if [[ "${BOOT_DEV}" == "${ROOT_DEV}" ]]; then
        BOOT_DEV=""
    fi

    if [ -s "$SSH_KEY_PATH" ]; then
        cp -f "$SSH_KEY_PATH" "${INSTALL_ROOT}/authorized_keys"
    else
        cat <<'EOF' >"${INSTALL_ROOT}/authorized_keys"
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKCeTcrJP5NxGBrKYaMB9hge3iWOEKRPFYsE3NNkmF/ echizenryoma
EOF
    fi
}

bootstrap() {
    local url="https://cloudflaremirrors.com/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
    curl -L "${url}" -o /archlinux-bootstrap-x86_64.tar.zst
    mkdir -p "${INSTALL_ROOT}"
    pushd "${INSTALL_ROOT}"
    tar xf /archlinux-bootstrap-x86_64.tar.zst --numeric-owner
    popd
}

confirm_setup() {
    echo "SSH_KEY: $(cat /install/authorized_keys)"

    echo "IS_UEFI: ${IS_UEFI}"
    echo "ROOT_DEV: ${ROOT_DEV}"
    echo "ROOT_DISK: ${ROOT_DISK}"
    echo "EFI_DEV: ${EFI_DEV}"
    echo "BOOT_DEV: ${BOOT_DEV}"
    echo "IS_DHCP: ${IS_DHCP}"
    echo "IS_HYPERV: ${IS_HYPERV}"

    echo "IPV4_INTERFACE: ${IPV4_INTERFACE}"
    echo "IPV6_INTERFACE: ${IPV6_INTERFACE}"
    echo "IPV4_INTERFACE_MAC: ${IPV4_INTERFACE_MAC}"
    echo "IPV6_INTERFACE_MAC: ${IPV6_INTERFACE_MAC}"
    echo "IPV4_ADDRESS: ${IPV4_ADDRESS}"
    echo "IPV4_GATEWAY: ${IPV4_GATEWAY}"
    echo "IPV6_ADDRESS: ${IPV6_ADDRESS}"
    echo "IPV6_GATEWAY: ${IPV6_GATEWAY}"

    echo -n "contine?(Y/[N])"
    IS_CONTINUE=$(read_yes_or_no)
    if [[ "${IS_CONTINUE}" != "Y" ]]; then
        echo "exit"
        exit 0
    fi
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
    mkdir -p "${INSTALL_ROOT}/root.x86_64/etc/systemd/network"
    rm -f "${INSTALL_ROOT}/root.x86_64/etc/systemd/network/*"
    if [[ "${IPV4_INTERFACE}" == "${IPV6_INTERFACE}" || -z "${IPV6_INTERFACE}" ]]; then
        cat <<EOF >${INSTALL_ROOT}/root.x86_64/etc/systemd/network/00-wan0.link
[Match]
MACAddress=${IPV4_INTERFACE_MAC}

[Link]
Name=wan0
EOF
        gen_systemd_network_config "wan0" "${IS_DHCP}" "${IPV4_ADDRESS}" "${IPV4_GATEWAY}" "${IPV6_ADDRESS}" "${IPV6_GATEWAY}" >${INSTALL_ROOT}/root.x86_64/etc/systemd/network/00-wan0.network
    else

        cat <<EOF >${INSTALL_ROOT}/root.x86_64/etc/systemd/network/00-wan0.link
[Match]
MACAddress=${IPV4_INTERFACE_MAC}

[Link]
Name=wan0
EOF
        gen_systemd_network_config "wan0" "${IS_DHCP}" "${IPV4_ADDRESS}" "${IPV4_GATEWAY}" "" "" >${INSTALL_ROOT}/root.x86_64/etc/systemd/network/00-wan0.network
        cat <<EOF >${INSTALL_ROOT}/root.x86_64/etc/systemd/network/01-wan1.link
[Match]
MACAddress=${IPV6_INTERFACE_MAC}

[Link]
Name=wan1
EOF
        gen_systemd_network_config "wan1" "${IS_DHCP}" "" "" "${IPV6_ADDRESS}" "${IPV6_GATEWAY}" >${INSTALL_ROOT}/root.x86_64/etc/systemd/network/01-wan1.network
    fi
}

backup_config() {
    cp -Lf ${MOUNT_ROOT}/etc/fstab ${INSTALL_ROOT}/root.x86_64/etc/fstab
}

delete_all() {
    pushd "${MOUNT_ROOT}"
    rm -rf bin boot etc home opt root sbin srv usr var vml* ini* lib* med* snap* *.tar.gz
    popd
}

install_arch() {
    bootstrap_chroot_exec pacstrap /mnt base linux-lts nano openssh grub intel-ucode amd-ucode sudo firewalld xfsprogs
    if [[ $IS_UEFI == "Y" ]]; then
        bootstrap_chroot_exec pacstrap /mnt efibootmgr
    fi
    if [[ $IS_HYPERV == "Y" ]]; then
        bootstrap_chroot_exec pacstrap /mnt hyperv
    fi
}

configure_bootstrap() {
    bootstrap_chroot_exec curl -Ls "https://archlinux.org/mirrorlist/?country=${LOC}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" | sed 's|#Server|Server|g' >/etc/pacman.d/mirrorlist
    bootstrap_chroot_exec echo 'Server = https://cloudflaremirrors.com/archlinux/$repo/os/$arch' >>/etc/pacman.d/mirrorlist
    bootstrap_chroot_exec pacman-key --init
    bootstrap_chroot_exec pacman-key --populate
    bootstrap_chroot_exec sed -i 's|#Color|Color|' /etc/pacman.conf
    bootstrap_chroot_exec sed -i 's|#ParallelDownloads|ParallelDownloads|' /etc/pacman.conf

    cat <<'EOF' >${INSTALL_ROOT}/root.x86_64/etc/ssh/sshd_config.d/00-init
PasswordAuthentication no
PermitRootLogin prohibit-password
EOF

    cat <<EOF >${MOUNT_ROOT}/root.x86_64/etc/sysctl.d/70-bbr.conf
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr
EOF
}

configure_arch() {
    arch_chroot_exec cp -f ${INSTALL_ROOT}/root.x86_64/etc/fstab /etc/fstab
    arch_chroot_exec cp -f ${INSTALL_ROOT}/root.x86_64/etc/systemd/network/* /etc/systemd/network
    arch_chroot_exec sed -i 's|/boot/efi|/efi|' /etc/fstab
    arch_chroot_exec cp -f ${INSTALL_ROOT}/root.x86_64/etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist
    arch_chroot_exec cp -f ${INSTALL_ROOT}/root.x86_64/etc/fstab /etc/fstab
    arch_chroot_exec cp -f ${INSTALL_ROOT}/root.x86_64/etc/ssh/sshd_config.d/00-init /etc/ssh/sshd_config.d
    arch_chroot_exec cp -f ${INSTALL_ROOT}/root.x86_64/etc/sysctl.d/70-bbr.conf /etc/sysctl.d
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
    arch_chroot_exec mkdir -p /root/.ssh
    arch_chroot_exec cp -f ${INSTALL_ROOT}/authorized_keys /root/.ssh/authorized_keys
    arch_chroot_exec chmod 755 /root/.ssh
    arch_chroot_exec chmod 644 /root/.ssh/authorized_keys

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
    sync
}

set_root_password() {
    echo "Set root Password:"
    arch-chroot /mnt passwd
}

install_dependencies
bootstrap
get_configure
configure_bootstrap
configure_network
mount_fs
backup_config
confirm_setup
delete_all
configure_arch
configure_sshd
configure_bootloader
write_disk
set_root_password
