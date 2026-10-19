#!/bin/bash
set -e

echo "Starting certificate renewal..."

SERVER_CN=$(grep '^cert ' /etc/openvpn/openvpn.conf | sed 's|.*/issued/||' | sed 's|\.crt$||')

if [[ -z "$SERVER_CN" ]]; then
    echo "Error: Could not determine server certificate CN from openvpn.conf"
    exit 1
fi

renew_cert() {
    local cn="$1"

    # Revoke any previously renewed cert so renew doesn't conflict
    if [[ -f "$EASYRSA_PKI/renewed/issued/${cn}.crt" ]]; then
        echo "Revoking previously renewed cert for: $cn"
        printf 'yes\n' | /usr/local/bin/easyrsa revoke-renewed "$cn"
    fi

    printf 'yes\nyes\n' | /usr/local/bin/easyrsa renew "$cn"
}

echo "Renewing server certificate ($SERVER_CN)..."
renew_cert "$SERVER_CN"

echo "Regenerating CRL..."
/usr/local/bin/easyrsa gen-crl
cp -f "$EASYRSA_PKI/crl.pem" "$OPENVPN/crl.pem"
chmod 644 "$OPENVPN/crl.pem"

for OVPN_FILE in /configs/*.ovpn; do
    [ -f "$OVPN_FILE" ] || continue
    USER=$(basename "$OVPN_FILE" .ovpn)
    echo "Renewing client certificate: $USER"
    renew_cert "$USER"
    /usr/local/bin/ovpn_getclient "$USER" > /configs/"$USER".ovpn
    sed -i -E "s/^remote [^ ]+ [0-9]+/remote ${VIRTUAL_HOST} ${EXTERNAL_PORT}/" /configs/"$USER".ovpn
done

echo "Restarting OpenVPN..."
pkill -f "openvpn --config" || true
sleep 2

echo "Done. All users must redownload their .ovpn configuration files."
