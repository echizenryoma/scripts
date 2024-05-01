#!/bin/bash

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
        if [[ -n $ipv4_gateway ]]; then
            config+="Gateway=${ipv4_gateway}\n"
        fi

        if [[ -n $ipv6_address ]]; then
            config+="Address=${ipv6_address}\nDNS=2606:4700:4700::1111\nIPv6AcceptRA=0\n"
        fi
        if [[ -n $ipv6_gateway ]]; then
            config+="\n[Route]\nGateway=${ipv6_gateway}\nGatewayOnLink=yes\n"
        fi
    fi
    echo -e $config
}

get_disk() {
    partition="$1"
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

source /install/.env
echo "IS_UEFI: ${IS_UEFI}"
echo "ROOT_DEV: ${ROOT_DEV}"
echo "EFI_DEV: ${EFI_DEV}"
echo "LOC: ${LOC}"
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

mount ${ROOT_DEV} /mnt
if [[ $IS_UEFI == "Y" ]]; then
    mkdir -p "/mnt/efi"
    mount $EFI_DEV "/mnt/efi"
fi

curl -Ls "https://archlinux.org/mirrorlist/?country=${LOC}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" | sed 's|#Server|Server|g' >/etc/pacman.d/mirrorlist
pacman-key --init
pacman-key --populate
sed -i 's|#Color|Color|' /etc/pacman.conf
sed -i 's|#ParallelDownloads|ParallelDownloads|' /etc/pacman.conf
cp /mnt/etc/fstab /etc/fstab
cd /mnt
rm -rf bin boot etc home opt root sbin srv usr var vml* ini* lib* med* snap* *.tar.gz
pacstrap /mnt base linux-lts linux-firmware nano openssh grub intel-ucode amd-ucode sudo firewalld xfsprogs
if [[ $IS_UEFI == "Y" ]]; then
    pacstrap /mnt efibootmgr
fi
if [[ $IS_HYPERV == "Y" ]]; then
    pacstrap /mnt hyperv
fi

cp /etc/fstab /mnt/etc/fstab # genfstab -U /mnt >> /mnt/etc/fstab
umount /etc/resolv.conf
sed -i 's|/boot/efi|/efi|' /mnt/etc/fstab
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

if [[ "${IPV4_INTERFACE}" == "${IPV6_INTERFACE}" || -z "${IPV6_INTERFACE}" ]]; then
    cat <<EOF >/mnt/etc/systemd/network/00-wan0.link
[Match]
MACAddress=${IPV4_INTERFACE_MAC}

[Link]
Name=wan0
EOF
    gen_systemd_network_config "wan0" "${IS_DHCP}" "${IPV4_ADDRESS}" "${IPV4_GATEWAY}" "${IPV6_ADDRESS}" "${IPV6_GATEWAY}" >/mnt/etc/systemd/network/00-wan0.network
else

    cat <<EOF >/mnt/etc/systemd/network/00-wan0.link
[Match]
MACAddress=${IPV4_INTERFACE_MAC}

[Link]
Name=wan0
EOF
    gen_systemd_network_config "wan0" "${IS_DHCP}" "${IPV4_ADDRESS}" "${IPV4_GATEWAY}" "" "" >/mnt/etc/systemd/network/00-wan0.network
    cat <<EOF >/mnt/etc/systemd/network/01-wan1.link
[Match]
MACAddress=${IPV6_INTERFACE_MAC}

[Link]
Name=wan1
EOF
    gen_systemd_network_config "wan1" "${IS_DHCP}" "" "" "${IPV6_ADDRESS}" "${IPV6_GATEWAY}" >/mnt/etc/systemd/network/01-wan1.network
fi
arch-chroot /mnt systemctl enable systemd-networkd
arch-chroot /mnt systemctl enable systemd-resolved

cat <<'EOF' >/mnt/etc/ssh/sshd_config.d/00-init
PasswordAuthentication no
PermitRootLogin prohibit-password
EOF

mkdir -p /mnt/root/.ssh
cat <<'EOF' >/mnt/root/.ssh/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKCeTcrJP5NxGBrKYaMB9hge3iWOEKRPFYsE3NNkmF/ echizenryoma
EOF
chmod 755 /mnt/root/.ssh
chmod 644 /mnt/root/.ssh/authorized_keys

arch-chroot /mnt systemctl enable sshd
arch-chroot /mnt sed -i "/Port 22$/a\Port 10022" /etc/ssh/sshd_config
arch-chroot /mnt firewall-offline-cmd --add-port=10022/tcp
arch-chroot /mnt systemctl enable firewalld

cat <<EOF >/mnt/etc/sysctl.d/70-bbr.conf
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr
EOF

if [[ $IS_HYPERV == "Y" ]]; then
    sed -i "s|^MODULES=(.*)|MODULES=(hv_storvsc hv_vmbus)|g" /mnt/etc/mkinitcpio.conf
fi
sed -i "s|PRESETS=(.*)|PRESETS=('default')|g" /mnt/etc/mkinitcpio.d/linux-lts.preset
sed -i "s|^HOOKS=(.*)|HOOKS=(base systemd autodetect microcode modconf kms keyboard block filesystems fsck)|g" /mnt/etc/mkinitcpio.conf
sed -i 's|#Color|Color|' /mnt/etc/pacman.conf
sed -i 's|#ParallelDownloads|ParallelDownloads|' /mnt/etc/pacman.conf
sed -i 's|# include \"/usr/share/nano/\*\.nanorc\"|include "/usr/share/nano/*.nanorc"|' /mnt/etc/nanorc
arch-chroot /mnt mkinitcpio -P
rm /mnt/boot/initramfs-linux-lts-fallback.img

sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"|g' /mnt/etc/default/grub
echo 'GRUB_SERIAL_COMMAND="serial --speed=115200"' >>/mnt/etc/default/grub
echo 'GRUB_EARLY_INITRD_LINUX_STOCK=""' >>/mnt/etc/default/grub
if [[ $IS_UEFI == "Y" ]]; then
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=arch
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    arch-chroot /mnt mkdir -p /efi/EFI/BOOT
    arch-chroot /mnt cp /efi/EFI/arch/grubx64.efi /efi/EFI/BOOT/BOOTX64.EFI
else
    ROOT_DISK=$(get_disk ${ROOT_DEV})
    arch-chroot /mnt grub-install --target=i386-pc ${ROOT_DISK} --force
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi

echo -e "Set root Password:\n"
arch-chroot /mnt passwd
