FROM alpine:latest

ENV DOMAIN=changeme \
    EXTERNAL_PORT=1194

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories && \
    apk add --update openvpn iptables bash easy-rsa openvpn-auth-pam supervisor pamtester nginx curl grep gosu && \
    ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/* && \
    mkdir -p /etc/nginx/sites-enabled && \
    mkdir -p /run/nginx

ADD sources/nginx-openvpn.conf /etc/nginx/sites-enabled/openvpn.conf
ADD sources/nginx.conf /etc/nginx/nginx.conf
ADD sources/supervisord.conf /etc/supervisord.conf

ENV OPENVPN=/etc/openvpn
ENV EASYRSA=/usr/share/easy-rsa
ENV EASYRSA_PKI=$OPENVPN/pki

ENV EASYRSA_CRL_DAYS=1460

# https://github.com/OpenVPN/easy-rsa/issues/333
ENV EASYRSA_CERT_EXPIRE=1460

ADD scripts/openvpn /usr/local/bin
RUN chmod a+x /usr/local/bin/*

ADD scripts /scripts
RUN chmod -R +x /scripts

ADD entrypoint.sh /entrypoint.sh
ADD moduser.sh /moduser.sh
RUN chmod +x /entrypoint.sh /moduser.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisord.conf"]

EXPOSE 80 1194
