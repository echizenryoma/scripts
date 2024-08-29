#!/bin/bash

install_dependencies() {
    apt update
    apt install -y coreutils gawk curl tar zstd
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

install_dependencies

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
if [[ $IS_UEFI == "Y" ]]; then
    EFI_DEV=$(get_mount_fs /boot/efi)
fi
BOOT_DEV=$(get_mount_fs /boot)
if [[ "${BOOT_DEV}" == "${ROOT_DEV}" ]]; then
    BOOT_DEV=""
fi

ARCHLINUX_BOOTSTRAP_URL="https://cloudflaremirrors.com/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
curl -L "${ARCHLINUX_BOOTSTRAP_URL}" -o /archlinux-bootstrap-x86_64.tar.zst
mkdir /install
cd /install
tar xf /archlinux-bootstrap-x86_64.tar.zst --numeric-owner

mkdir -p /install/root.x86_64/install
if [ -s "$SSH_KEY_PATH" ]; then
    cp -f "$SSH_KEY_PATH" /install/root.x86_64/install/authorized_keys
else
    cat <<'EOF' >/install/root.x86_64/install/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKCeTcrJP5NxGBrKYaMB9hge3iWOEKRPFYsE3NNkmF/ echizenryoma
EOF
fi

cat <<EOF >/install/root.x86_64/install/.env
IS_UEFI=${IS_UEFI}
ROOT_DEV=${ROOT_DEV}
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
curl -Ls "https://raw.githubusercontent.com/echizenryoma/scripts/main/arch/install/setup.bash" -o /install/root.x86_64/install/setup.bash
chmod +x /install/root.x86_64/install/setup.bash
/install/root.x86_64/bin/arch-chroot /install/root.x86_64/ /install/setup.bash
