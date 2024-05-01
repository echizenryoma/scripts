#!/bin/bash

install_dependencies() {
    apt update && apt install -y coreutils gawk jq curl tar
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

get_loc() {
    local loc
    loc=$(curl -Ls "ipinfo.io" | jq -r '.country')
    if [[ -z $loc ]]; then
        loc=$(curl -Ls "6.ipinfo.io" | jq -r '.country')
    fi
    echo "$loc"
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

LOC=$(get_loc)
echo "LOC: ${LOC}"

IS_UEFI=$(is_uefi)
echo "UEFI: ${IS_UEFI}"

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

ARCHLINUX_BOOTSTRAP_URL=$(curl -Ls "https://archlinux.org/mirrorlist/?country=${LOC}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" | grep "Server" | sed 's|$repo/os/$arch|iso/latest/archlinux-bootstrap-x86_64.tar.gz|g' | awk '{print $3}' | head -n 1)
curl -L "${ARCHLINUX_BOOTSTRAP_URL}" -o /archlinux-bootstrap-x86_64.tar.gz
mkdir /install
cd /install
tar xzf /archlinux-bootstrap-x86_64.tar.gz --numeric-owner

mkdir -p /install/root.x86_64/install
cat <<EOF >/install/root.x86_64/install/.env
IS_UEFI=${IS_UEFI}
ROOT_DEV=${ROOT_DEV}
EFI_DEV=${EFI_DEV}
BOOT_DEV=${BOOT_DEV}
LOC=${LOC}
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
curl -Ls "https://github.com/echizenryoma/scripts/raw/main/arch/install/setup.bash" -o /install/root.x86_64/install/setup.bash
chmod +x /install/root.x86_64/install/setup.bash
/install/root.x86_64/bin/arch-chroot /install/root.x86_64/ /install/setup.bash
