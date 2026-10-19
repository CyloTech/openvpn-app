#!/usr/bin/env bash
set -x

###########################[ SUPERVISOR SCRIPTS ]###############################

if [ ! -f /etc/app_configured ]; then
    mkdir -p /etc/supervisor/conf.d
cat << EOF >> /etc/supervisor/conf.d/openvpn.conf
[program:openvpn]
command=/bin/bash -c "TERM=xterm /usr/local/bin/ovpn_run"
autostart=true
autorestart=true
priority=1
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF >> /etc/supervisor/conf.d/nginx.conf
[program:nginx]
command=/bin/bash -c "TERM=xterm /usr/local/bin/ovpn_run"
autostart=true
autorestart=true
priority=1
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
fi

###########################[ OPENVPN SETUP ]###############################

# Needed for update
mkdir /var/tmp/nginx/

# Move this from old version so updates work (can be deleted after first forced update)
if [ -f /.htpasswd ]; then
    mv /.htpasswd /etc/openvpn/.htpasswd
fi

if [ ! $(ls -A /configs) ]; then
    echo yes | usr/local/bin/ovpn_genconfig -b -u udp://${DOMAIN}:${EXTERNAL_PORT} -C 'AES-256-GCM' -a 'SHA384'
    echo yes | /usr/local/bin/ovpn_initpki nopass
    echo yes | /usr/local/bin/easyrsa build-client-full config nopass
    echo yes | /usr/local/bin/ovpn_getclient config > /configs/config.ovpn

    printf "${OPENVPN_USER}:$(openssl passwd -apr1 ${OPENVPN_PASSWORD})\n" >> /etc/openvpn/.htpasswd
    sed -i 's#localhost#'${DOMAIN}'#g' /etc/nginx/sites-enabled/openvpn.conf
fi

IP_SUBNET=$(ifconfig eth0 | grep ' inet ' | awk '{print $2}' | awk -F ':' '{print $2}' | awk -F '.' '{print $1"."$2"."$3".0"}')

# Delete any config errors 31/03/24, inet6 added extra lines
sed -i '/\.\.\.0/d' /etc/openvpn/openvpn.conf

# Reset IP subnet in case of migration
sed -i '/push "route/d' /etc/openvpn/openvpn.conf
sed -i '/push route/d' /etc/openvpn/openvpn.conf
echo "push \"route ${IP_SUBNET} 255.255.255.0\"" >> /etc/openvpn/openvpn.conf

sed -i '/tls-auth/d' /etc/openvpn/openvpn.conf
echo 'tls-auth /etc/openvpn/pki/ta.key 0' >> /etc/openvpn/openvpn.conf

# Reset ports in case of migration
while read -r CONFIG
do
    sed -i -E "s/remote ${VIRTUAL_HOST} [0-9]*/remote ${VIRTUAL_HOST} ${EXTERNAL_PORT}/g" /configs/${CONFIG}
done < <(ls -la /configs/ | grep 'ovpn' | awk '{print $9}')

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured

    while read -r CONFIG; do
        USER=$(echo ${CONFIG} | sed 's/.ovpn//g')
        grep -Pzo '(-----BEGIN OpenVPN Static key V1-----)[\sa-zA-Z0-9]*(-----END OpenVPN Static key V1-----)' /configs/"$USER".ovpn > /tmp/"$USER"_key
        USER_SHA=$(sha1sum < /tmp/"$USER"_key)
        grep -Pzo '(-----BEGIN OpenVPN Static key V1-----)[\sa-zA-Z0-9]*(-----END OpenVPN Static key V1-----)' /etc/openvpn/pki/ta.key > /tmp/ta_key
        TA_SHA=$(sha1sum < /tmp/ta_key)
        echo "Comparing $USER_SHA and $TA_SHA"
        if [ "$USER_SHA" != "$TA_SHA" ]; then
            echo yes | /usr/local/bin/easyrsa build-client-full "$USER" nopass
            echo yes | /usr/local/bin/ovpn_getclient "$USER" > /configs/"$USER".ovpn
        fi
    done < <(ls -la /configs/ | grep 'ovpn' | awk '{print $9}')

    until [[ $(curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/${INSTANCE_ID}" | grep '200') ]]
        do
        sleep 5
    done
fi

# Some failure happened? Reinitialise
# if ! ls -la /etc/openvpn/pki | grep -q 'safessl-easyrsa.cnf' || [ "$(ls -la /etc/openvpn/pki | grep 'safessl-easyrsa.cnf' | awk '{print $5}')" -eq "0" ] ; then
#     echo yes | /usr/local/bin/ovpn_initpki nopass
#     while read -r CONFIG; do
#         USER=$(echo ${CONFIG} | sed 's/.ovpn//g')
#         echo yes | /usr/local/bin/easyrsa build-client-full "$USER" nopass
#         echo yes | /usr/local/bin/ovpn_getclient "$USER" > /configs/"$USER".ovpn
#     done < <(ls -la /configs/ | grep 'ovpn' | awk '{print $9}')
# fi

chmod 775 /configs/

exec /usr/bin/supervisord -n -c /etc/supervisord.conf