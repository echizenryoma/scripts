#!/bin/bash

source /etc/environment

pacman -Sy --noconfirm --needed cockpit cockpit-storaged cockpit-pcp cockpit-podman networkmanager

mkdir -p /etc/systemd/system/cockpit.socket.d
cat <<EOF >/etc/systemd/system/cockpit.socket.d/listen.conf
[Socket]
ListenStream=
ListenStream=127.0.0.1:19090
FreeBind=yes
EOF

cat <<EOF >/etc/cockpit/cockpit.conf
[WebService]
Origins=https://${CER_DOMAIN} https://${PROXY_DOMAIN} wss://${CER_DOMAIN} wss://${PROXY_DOMAIN}
ProtocolHeader=X-Forwarded-Proto
ForwardedForHeader=X-Forwarded-For
UrlRoot=/cockpit
EOF

mkdir -p /etc/nginx/conf.d/default.d
cat <<"EOF" >/etc/nginx/conf.d/default.d/30-cockpit.conf
location = /cockpit {
    return 301 /cockpit/;
}

location /cockpit/ {
    proxy_pass https://127.0.0.1:19090/cockpit/;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_buffering off;

    gzip off;
}
EOF

ln -sf /var/ssl/${PROXY_DOMAIN}.{key,crt} /etc/cockpit/ws-certs.d/

systemctl daemon-reload
systemctl enable --now NetworkManager.service
systemctl enable --now pmlogger.service
systemctl enable --now cockpit.socket
