#!/bin/bash

INSTALL_ROOT="/install"
BOOSTRAP_ROOT="${INSTALL_ROOT}/root.x86_64"
MOUNT_ROOT="/mnt"
ROOT_PASS=""

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
    if [[ $partition == /dev/nvme* ]]; then
        disk=$(echo $partition | sed 's/p[0-9]*$//')
    else
        disk=$(echo $partition | sed 's/[0-9]*$//')
    fi
    echo $disk
}

get_fs() {
    local partition="$1"
    df -T "${partition}" | tail -n 1 | awk '{print $2}'
}

get_cpu_vendor() {
    local cpu_vendor_id=$(cat /proc/cpuinfo | grep 'vendor_id' | head -n 1 | awk '{print $3}')
    if [[ ${cpu_vendor_id} == *"Intel"* ]]; then
        echo "Intel"
    elif [[ ${cpu_vendor_id} == *"AMD"* ]]; then
        echo "AMD"
    fi
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

set_root_password() {
    local password1
    local password2

    read -s -p "Enter password: " password1
    echo

    read -s -p "Enter password again: " password2
    echo

    if [[ "$password1" == "$password2" ]]; then
        ROOT_PASS="$password1"
    else
        echo "The passwords you entered twice do not match. Please try again."
        set_root_password
    fi
}

get_configure() {
    LOC=$(curl --connect-timeout 3 -Ls "https://myip.rdbg.net/loc")
    CPU_VENDOR=$(get_cpu_vendor)

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
    if [[ -z "${SSH_KEY_PATH}" ]]; then
        SSH_KEY_PATH=/root/.ssh/authorized_keys
    fi

    echo -n "Enable DHCP?(Y/[N]): "
    IS_DHCP=$(read_yes_or_no)
    echo -n "Is Hyper-V?(Y/[N]): "
    IS_HYPERV=$(read_yes_or_no)

    ROOT_DEV=$(get_mount_fs /)
    ROOT_DISK=$(get_disk ${ROOT_DEV})
    ROOT_FS=$(get_fs ${ROOT_DEV})
    if [[ $IS_UEFI == "Y" ]]; then
        EFI_DEV=$(get_mount_fs /boot/efi)
    fi
    BOOT_DEV=$(get_mount_fs /boot)
    if [[ "${BOOT_DEV}" == "${ROOT_DEV}" ]]; then
        BOOT_DEV=""
    else
        BOOT_FS=$(get_fs ${BOOT_DEV})
    fi

    mkdir -p "${BOOSTRAP_ROOT}/root/.ssh"
    if [ -s "$SSH_KEY_PATH" ]; then
        cp -f "$SSH_KEY_PATH" "${BOOSTRAP_ROOT}/root/.ssh/authorized_keys"
    else
        cat <<'EOF' >"${BOOSTRAP_ROOT}/root/.ssh/authorized_keys"
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKCeTcrJP5NxGBrKYaMB9hge3iWOEKRPFYsE3NNkmF/ echizenryoma
EOF
    fi
    set_root_password
}

bootstrap() {
    local url="https://cloudflaremirrors.com/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
    if [[ "$LOC" == "CN" ]]; then
        url="https://mirrors.ustc.edu.cn/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
    fi
    curl -L "${url}" -o /archlinux-bootstrap-x86_64.tar.zst
    mkdir -p "${INSTALL_ROOT}"
    pushd "${INSTALL_ROOT}"
    tar xf /archlinux-bootstrap-x86_64.tar.zst --numeric-owner
    popd
}

confirm_setup() {
    echo "SSH_KEY: $(cat ${BOOSTRAP_ROOT}/root/.ssh/authorized_keys)"

    echo "LOC: ${LOC}"
    echo "CPU_VENDOR: ${CPU_VENDOR}"
    echo "IS_UEFI: ${IS_UEFI}"
    echo "ROOT_DEV: ${ROOT_DEV}"
    echo "ROOT_DISK: ${ROOT_DISK}"
    echo "ROOT_FS: ${ROOT_FS}"
    echo "EFI_DEV: ${EFI_DEV}"
    echo "BOOT_DEV: ${BOOT_DEV}"
    echo "BOOT_FS: ${BOOT_FS}"
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
    mkdir -p "${BOOSTRAP_ROOT}${INSTALL_ROOT}"
    cat <<EOF >${BOOSTRAP_ROOT}${INSTALL_ROOT}/.env
LOC=${LOC}
ROOT_PASS=${ROOT_PASS}
CPU_VENDOR=${CPU_VENDOR}
IS_UEFI=${IS_UEFI}
ROOT_DEV=${ROOT_DEV}
ROOT_DISK=${ROOT_DISK}
ROOT_FS=${ROOT_FS}
EFI_DEV=${EFI_DEV}
BOOT_DEV=${BOOT_DEV}
BOOT_FS=${BOOT_FS}
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
    local url="https://raw.githubusercontent.com/echizenryoma/scripts/main/arch/setup.bash"
    if [[ "$LOC" == "CN" ]]; then
        url="https://gitlab.com/ryomadev/scripts/-/raw/main/arch/setup.bash?ref_type=heads&inline=false"
    fi
    curl -Ls "$url" -o ${BOOSTRAP_ROOT}${INSTALL_ROOT}/setup.bash
    chmod +x ${BOOSTRAP_ROOT}${INSTALL_ROOT}/setup.bash
    bootstrap_chroot_exec ${INSTALL_ROOT}/setup.bash
}

install_dependencies
get_configure
confirm_setup
bootstrap
save_configure
install_arch
