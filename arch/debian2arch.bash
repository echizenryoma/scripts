#!/bin/bash

INSTALL_ROOT="/install"
BOOSTRAP_ROOT="${INSTALL_ROOT}/root.x86_64"
MOUNT_ROOT="/mnt"

bootstrap_chroot_exec() {
    ${BOOSTRAP_ROOT}/bin/arch-chroot "${BOOSTRAP_ROOT}" bash -c "$*"
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

    mkdir -p "${BOOSTRAP_ROOT}/root/.ssh"
    if [ -s "$SSH_KEY_PATH" ]; then
        cp -f "$SSH_KEY_PATH" "${BOOSTRAP_ROOT}/root/.ssh/authorized_keys"
    else
        cat <<'EOF' >"${BOOSTRAP_ROOT}/root/.ssh/authorized_keys"
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
    echo "SSH_KEY: $(cat ${BOOSTRAP_ROOT}/${INSTALL_ROOT}/authorized_keys)"

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

save_configure() {
    mkdir -p "${BOOSTRAP_ROOT}/${INSTALL_ROOT}"
    cat <<EOF >${BOOSTRAP_ROOT}/${INSTALL_ROOT}/.env
IS_UEFI=${IS_UEFI}
ROOT_DEV=${ROOT_DEV}
ROOT_DISK=${ROOT_DISK}
EFI_DEV=${EFI_DEV}
BOOT_DEV=${BOOT_DEV}
IS_DHCP=${IS_DHCP}
IS_HYPERV=${IS_HYPERV}
IPV4_INTERFACE=${IPV4_INTERFACE}
IPV6_INTERFACE=${IPV6_INTERFACE}
IPV4_INTERFACE_MAC=${IPV4_INTERFACE_MAC}
IPV6_INTERFACE_MAC=${IPV6_INTERFACE_MAC}
IPV4_ADDRESS=${IPV4_ADDRESS}
IPV4_GATEWAY=${IPV4_GATEWAY}
IPV6_ADDRESS=${IPV6_ADDRESS}
IPV6_GATEWAY=${IPV6_GATEWAY}
EOF
}

install_arch() {
    curl -Ls "https://raw.githubusercontent.com/echizenryoma/scripts/main/arch/setup.bash" -o ${BOOSTRAP_ROOT}/${INSTALL_ROOT}/setup.bash
    chmod +x ${BOOSTRAP_ROOT}/${INSTALL_ROOT}/setup.bash
    bootstrap_chroot_exec ${INSTALL_ROOT}/setup.bash
}

install_dependencies
bootstrap
get_configure
configure_bootstrap
mount_fs
backup_config
confirm_setup
save_configure
install_arch
