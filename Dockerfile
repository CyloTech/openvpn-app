FROM alpine:latest

ENV DOMAIN=changeme
ENV EXTERNAL_PORT=1194

# Testing: pamtester
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories && \
    apk add --update openvpn iptables bash easy-rsa openvpn-auth-pam supervisor pamtester nginx && \
    ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/* && \
    mkdir -p /etc/nginx/sites-enabled && \
    mkdir -p /run/nginx

ADD sources/nginx-openvpn.conf /etc/nginx/sites-enabled/openvpn.conf
ADD sources/nginx.conf /etc/nginx/nginx.conf
ADD sources/supervisord.conf /etc/supervisor.d/supervisord.ini

# Needed by scripts
ENV OPENVPN /etc/openvpn
ENV EASYRSA /usr/share/easy-rsa
ENV EASYRSA_PKI $OPENVPN/pki
ENV EASYRSA_VARS_FILE $OPENVPN/vars

# Prevents refused client connection because of an expired CRL
ENV EASYRSA_CRL_DAYS 3650

ADD scripts/openvpn /usr/local/bin
RUN chmod a+x /usr/local/bin/*

# Add support for OTP authentication using a PAM module
ADD scripts /scripts
RUN chmod -R +x /scripts
ADD sources/supervisord.conf /etc/supervisord.conf

CMD ["/scripts/start.sh"]

EXPOSE 80 1194