#!/bin/bash

mkdir -p /var/ssl
mkdir -p /var/acme.sh

cat <<'EOF' >/var/ssl/acme-cron
#!/bin/bash

ACME_HOME=/var/acme.sh
SSL_DIR=/var/ssl

domain=$1
domain_txt="${SSL_DIR}/${domain}.txt"
domain_env="${SSL_DIR}/${domain}.env"
domain_req=$(cat ${domain_txt} | sed 's|^|-d |' | tr "\n" " ")

echo "domain_req: ${domain_req}"
source "${domain_env}"

ssl_crt_path="${SSL_DIR}/${domain}.crt"
ssl_key_path="${SSL_DIR}/${domain}.key"

case ${ACME_TYPE} in
  "webroot")
    docker run --rm --network=host \
      -v /var/acme.sh:/acme.sh \
      -v /var/ssl:/var/ssl \
      -v /usr/share/nginx/html:/usr/share/nginx/html \
      --env-file ${domain_env} \
      neilpang/acme.sh --issue ${domain_req} --server ${ACME_SERVER} --keylength ec-384 -w /usr/share/nginx/html --fullchain-file ${ssl_crt_path} --key-file ${ssl_key_path} --debug
    ;;
  "dns")
    docker run --rm --network=host \
      -v /var/acme.sh:/acme.sh \
      -v /var/ssl:/var/ssl \
      --env-file ${domain_env} \
      neilpang/acme.sh --issue ${domain_req} --server ${ACME_SERVER} --keylength ec-384 --dns ${ACME_DNS} --fullchain-file ${ssl_crt_path} --key-file ${ssl_key_path} --debug
    ;;
esac
EOF

cat <<'EOF' >/var/ssl/update
#!/bin/sh

domain=$1
/var/ssl/acme-cron $domain
ret=$?
if [ $ret -eq 0 ]; then
    chmod a+r /var/ssl/$domain.crt
    chmod a+r /var/ssl/$domain.key
    bash /var/ssl/$domain.sh
fi
EOF
chmod +x /var/ssl/update
chmod +x /var/ssl/acme-cron

cat <<EOF >/etc/systemd/system/update-ssl@.service
[Unit]
Description=Update Certificates for %i

[Service]
Type=simple
TimeoutStartSec=600
RemainAfterExit=no
ExecStart=/var/ssl/update %i
EOF

cat <<EOF >/etc/systemd/system/update-ssl@.timer
[Unit]
Description=Update Certificates Timer for %i

[Timer]
OnCalendar=weekly
Unit=update-ssl@%i.service
RandomizedDelaySec=5day

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
