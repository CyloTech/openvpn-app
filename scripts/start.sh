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

if [ ! -f /etc/app_configured ]; then
    /usr/local/bin/ovpn_genconfig -b -u udp://${DOMAIN}:${EXTERNAL_PORT} -C 'AES-256-CBC' -a 'SHA384'
    /usr/local/bin/ovpn_initpki nopass
    /usr/local/bin/easyrsa build-client-full config nopass
    /usr/local/bin/ovpn_getclient config > /configs/config.ovpn

    printf "${OPENVPN_USER}:$(openssl passwd -crypt ${OPENVPN_PASSWORD})\n" >> /.htpasswd
    sed -i 's#localhost#'${DOMAIN}'#g' /etc/nginx/sites-enabled/openvpn.conf
fi

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
fi

exec /usr/bin/supervisord -n -c /etc/supervisord.conf