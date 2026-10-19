#!/bin/bash

NEW_PASSWORD="$1"

if [[ -z "${NEW_PASSWORD}" ]]; then
    echo "Usage: /moduser.sh <new_password>"
    exit 1
fi

USERNAME=$(head -1 /etc/openvpn/.htpasswd | cut -d: -f1)

if [[ -z "${USERNAME}" ]]; then
    echo "Error: No user found in /etc/openvpn/.htpasswd"
    exit 1
fi

sed -i '/\b'${USERNAME}':/d' /etc/openvpn/.htpasswd

if [[ ! -f /etc/openvpn/pki/issued/${USERNAME}.crt ]]; then
    echo yes | /usr/local/bin/easyrsa build-client-full ${USERNAME} nopass
fi

rm -f /configs/${USERNAME}.ovpn
/usr/local/bin/ovpn_getclient ${USERNAME} > /configs/${USERNAME}.ovpn
sed -i -E "s/^remote [^ ]+ [0-9]+/remote ${VIRTUAL_HOST} ${EXTERNAL_PORT}/" /configs/${USERNAME}.ovpn

printf "${USERNAME}:$(openssl passwd -apr1 ${NEW_PASSWORD})\n" >> /etc/openvpn/.htpasswd
