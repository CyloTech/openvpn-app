#!/bin/bash
set -x

CONFIG_FLAG="/etc/app_configured"

# =============================================================================
# Platform Callback
# =============================================================================

callback_installed() {
    if [[ "${SKIP_APPBOX_CALLBACK:-0}" == "1" ]]; then
        echo "Skipping Appbox callback (SKIP_APPBOX_CALLBACK=1)"
        return 0
    fi

    local callback_url="https://api.cylo.net/v1/apps/installed/${INSTANCE_ID}"
    local headers=(
        -H "Accept: application/json"
        -H "Content-Type:application/json"
    )

    if [[ -n "${CALLBACK_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: Bearer ${CALLBACK_TOKEN}")
    fi

    until curl -fsS -o /dev/null "${headers[@]}" -X POST "${callback_url}"; do
        sleep 5
    done
}

# =============================================================================
# Per-boot setup
# =============================================================================

mkdir -p /var/tmp/nginx/

# Migration: move .htpasswd from old location (pre-2.0 images stored it at /)
if [[ -f /.htpasswd ]]; then
    mv /.htpasswd /etc/openvpn/.htpasswd
fi

# Fresh install: initialize PKI and create default VPN client
if [[ -z "$(ls -A /configs 2>/dev/null)" ]]; then
    echo yes | /usr/local/bin/ovpn_genconfig -b -u udp://${DOMAIN}:${EXTERNAL_PORT} -C 'AES-256-GCM' -a 'SHA384'
    echo yes | /usr/local/bin/ovpn_initpki nopass
    echo yes | /usr/local/bin/easyrsa build-client-full config nopass
    /usr/local/bin/ovpn_getclient config > /configs/config.ovpn

    printf "${OPENVPN_USER}:$(openssl passwd -apr1 ${OPENVPN_PASSWORD})\n" >> /etc/openvpn/.htpasswd
    sed -i 's#localhost#'${DOMAIN}'#g' /etc/nginx/sites-enabled/openvpn.conf
fi

# Keep ovpn_env.sh in sync with current port/host (handles server migration)
if [[ -f /etc/openvpn/ovpn_env.sh ]]; then
    sed -i -E "s/^declare -x OVPN_CN=.*/declare -x OVPN_CN='${VIRTUAL_HOST}'/" /etc/openvpn/ovpn_env.sh
    sed -i -E "s/^declare -x OVPN_PORT=.*/declare -x OVPN_PORT='${EXTERNAL_PORT}'/" /etc/openvpn/ovpn_env.sh
fi

# Reconfigure on every boot (handles server migration)
IP_SUBNET=$(ifconfig eth0 | grep ' inet ' | awk '{print $2}' | awk -F ':' '{print $2}' | awk -F '.' '{print $1"."$2"."$3".0"}')

sed -i '/\.\.\.0/d' /etc/openvpn/openvpn.conf

sed -i '/push "route/d' /etc/openvpn/openvpn.conf
sed -i '/push route/d' /etc/openvpn/openvpn.conf
echo "push \"route ${IP_SUBNET} 255.255.255.0\"" >> /etc/openvpn/openvpn.conf

sed -i '/tls-auth/d' /etc/openvpn/openvpn.conf
echo 'tls-auth /etc/openvpn/pki/ta.key 0' >> /etc/openvpn/openvpn.conf

while read -r CONFIG; do
    sed -i -E "s/remote ${VIRTUAL_HOST} [0-9]*/remote ${VIRTUAL_HOST} ${EXTERNAL_PORT}/g" /configs/${CONFIG}
done < <(ls -la /configs/ | grep 'ovpn' | awk '{print $9}')

# =============================================================================
# First boot of this container image
# =============================================================================

if [[ ! -f "${CONFIG_FLAG}" ]]; then
    touch "${CONFIG_FLAG}"

    # Upgrade: regenerate client certs if TLS key has changed
    while read -r CONFIG; do
        USER=$(echo ${CONFIG} | sed 's/.ovpn//g')
        grep -Pzo '(-----BEGIN OpenVPN Static key V1-----)[\sa-zA-Z0-9]*(-----END OpenVPN Static key V1-----)' /configs/"$USER".ovpn > /tmp/"$USER"_key
        USER_SHA=$(sha1sum < /tmp/"$USER"_key)
        grep -Pzo '(-----BEGIN OpenVPN Static key V1-----)[\sa-zA-Z0-9]*(-----END OpenVPN Static key V1-----)' /etc/openvpn/pki/ta.key > /tmp/ta_key
        TA_SHA=$(sha1sum < /tmp/ta_key)
        if [[ "$USER_SHA" != "$TA_SHA" ]]; then
            echo yes | /usr/local/bin/easyrsa build-client-full "$USER" nopass
            /usr/local/bin/ovpn_getclient "$USER" > /configs/"$USER".ovpn
        fi
    done < <(ls -la /configs/ | grep 'ovpn' | awk '{print $9}')

    callback_installed
fi

chmod 775 /configs/

exec "$@"
