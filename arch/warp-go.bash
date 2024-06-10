#!/bin/bash

gen_warp_ipv6() {
    sed -i 's|^#precedence\s\+::ffff:0:0/96\s\+100|precedence ::ffff:0:0/96  100|' /etc/gai.conf
    mkdir -p /etc/systemd/system/warp-go.service.d/
    cat >/etc/systemd/system/warp-go.service.d/override.conf <<EOF
[Service]
ExecStartPost=/bin/bash -c "/opt/warp-go/ExecStartPost.sh ipv6.google.com &"
EOF

    cat >/opt/warp-go/warp.conf <<EOF
[Account]
$(grep device_id wgcf-account.toml | sed 's|device_id|Device|' | tr -d "'")
$(grep PrivateKey wgcf-profile.conf)
$(grep access_token wgcf-account.toml | sed 's|access_token|Token|' | tr -d "'")
Type=free

[Device]
Name=WARP
MTU=1420

[Peer]
$(grep PublicKey wgcf-profile.conf)
$(grep Endpoint wgcf-profile.conf)
KeepAlive=5
AllowedIPs=::/0
EOF
}

gen_warp_ipv4() {
    local endpoint_ipv6_addr=$(nslookup -type=AAAA engage.cloudflareclient.com | sed '2d' | grep Address | head -n 1 | awk '{print $2}')
    mkdir -p /etc/systemd/system/warp-go.service.d/
    cat >/etc/systemd/system/warp-go.service.d/override.conf <<EOF
[Service]
ExecStartPost=/bin/bash -c "/opt/warp-go/ExecStartPost.sh 1.1.1.1 &"
EOF
    cat >/opt/warp-go/warp.conf <<EOF
[Account]
$(grep device_id wgcf-account.toml | sed 's|device_id|Device|' | tr -d "'")
$(grep PrivateKey wgcf-profile.conf)
$(grep access_token wgcf-account.toml | sed 's|access_token|Token|' | tr -d "'")
Type=free

[Device]
Name=WARP
MTU=1420

[Peer]
$(grep PublicKey wgcf-profile.conf)
Endpoint=[${endpoint_ipv6_addr}]:2408
KeepAlive=5
AllowedIPs=0.0.0.0/0
EOF
}

pacman -Sy --noconfirm --needed tar gzip curl wireguard-tools wgcf
bash <(curl -Ls https://raw.githubusercontent.com/echizenryoma/scripts/main/update/warp-go.bash)

curl -Ls "https://gitlab.com/ProjectWARP/warp-go/-/raw/master/systemd/warp-go.service" -o /etc/systemd/system/warp-go.service
sed -i 's|--foreground||' /etc/systemd/system/warp-go.service

wgcf register --accept-tos
wgcf generate
sed -i 's|\s*=\s*|=|g' wgcf-account.toml
sed -i 's|\s*=\s*|=|g' wgcf-profile.conf

cat >/opt/warp-go/ExecStartPost.sh <<'EOF'
#!/bin/bash

CheckDomain=$1
echo "CheckDomain: $CheckDomain"

while true; do
    sleep 30
    echo "pinging $CheckDomain ..."
    if ! ping -c 3 $CheckDomain &> /dev/null; then
        echo "ping -I WARP $CheckDomain failed"
        systemctl restart warp-go.service
        exit 0
    fi
    echo "ping $CheckDomain OK"
done
EOF
chmod +x /opt/warp-go/ExecStartPost.sh

echo -n "WARP IP version?(4/6)"
read warp_ip_version
case "${warp_ip_version}" in
"6")
    gen_warp_ipv6
    ;;
"4")
    gen_warp_ipv4
    ;;
*)
    echo "invalid ip version"
    exit -1
    ;;
esac
systemctl daemon-reload
systemctl enable --now warp-go.service
