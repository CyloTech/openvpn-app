#!/usr/bin/env bash

EXPECTED_ARGS=2
E_BADARGS=65

if [ $# -ne $EXPECTED_ARGS ]
    then
    echo "Usage: `basename $0` <username> <password>"
    exit $E_BADARGS
fi

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

USERNAME=${1}
PASSWORD=${2}

sed -i '/\b'${USERNAME}':/d' /etc/openvpn/.htpasswd

if [[ ! -f /etc/openvpn/pki/issued/${USERNAME}.crt ]]; then
    echo yes | /usr/local/bin/easyrsa build-client-full ${USERNAME} nopass
fi

rm -f /configs/${USERNAME}.ovpn
/usr/local/bin/ovpn_getclient ${USERNAME} > /configs/${USERNAME}.ovpn
sed -i -E "s/^remote [^ ]+ [0-9]+/remote ${VIRTUAL_HOST} ${EXTERNAL_PORT}/" /configs/${USERNAME}.ovpn

printf "${USERNAME}:$(openssl passwd -apr1 ${PASSWORD})\n" >> /etc/openvpn/.htpasswd
