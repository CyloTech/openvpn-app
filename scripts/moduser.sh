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

rm -f /configs/${USERNAME}.ovpn
sed '/\b'${USERNAME}':/d' /etc/openvpn/.htpasswd

/usr/local/bin/easyrsa build-client-full ${USERNAME} nopass
/usr/local/bin/ovpn_getclient config > /configs/${USERNAME}.ovpn

printf "${USERNAME}:$(openssl passwd -crypt ${PASSWORD})\n" >> /etc/openvpn/.htpasswd