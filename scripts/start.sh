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

# Move this from old version so updates work (can be deleted after first forced update)
if [ -f /.htpasswd ]; then
    mv /.htpasswd /etc/openvpn/.htpasswd
fi

if [ ! -f /configs/config.ovpn ]; then
    /usr/local/bin/ovpn_genconfig -b -u udp://${DOMAIN}:${EXTERNAL_PORT} -C 'AES-256-CBC' -a 'SHA384'
    /usr/local/bin/ovpn_initpki nopass
    /usr/local/bin/easyrsa build-client-full config nopass
    /usr/local/bin/ovpn_getclient config > /configs/config.ovpn

    printf "${OPENVPN_USER}:$(openssl passwd -crypt ${OPENVPN_PASSWORD})\n" >> /etc/openvpn/.htpasswd
    sed -i 's#localhost#'${DOMAIN}'#g' /etc/nginx/sites-enabled/openvpn.conf
fi

IP_SUBNET=$(ifconfig eth0 | grep inet | awk '{print $2}' | awk -F ':' '{print $2}' | awk -F '.' '{print $1"."$2"."$3".0"}')

# Reset IP subnet in case of migration
sed -i '/push route/d' /etc/openvpn/openvpn.conf
echo "push route ${IP_SUBNET} 255.255.255.0" >> /etc/openvpn/openvpn.conf

# Reset ports in case of migration
while read -r CONFIG
do
    sed -i -E "s/remote ${VIRTUAL_HOST} [0-9]*/remote ${VIRTUAL_HOST} ${EXTERNAL_PORT}/g" /configs/${CONFIG}
done < <(ls -la /configs/ | grep 'ovpn' | awk '{print $9}')

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured

    until [[ $(curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/${INSTANCE_ID}" | grep '200') ]]
        do
        sleep 5
    done
fi

exec /usr/bin/supervisord -n -c /etc/supervisord.conf