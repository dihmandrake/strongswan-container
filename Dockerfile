ARG STRONGSWAN_PREFIX="/usr"
ARG STRONGSWAN_SYS_CONF_DIR="/etc/strongswan"
ARG STRONGSWAN_LIBEXEC_DIR="/usr/libexec"
ARG STRONGSWAN_IPSEC_DIR="/usr/libexec/ipsec"
ARG STRONGSWAN_PID_DIR="/var/run"
ARG STRONGSWAN_VERSION="5.9.2"

ARG ROOT_FOLDER_STRUCTURE="/strongswan"


FROM gcc:11.1.0 as strongswan-configure

COPY strongswan "/strongswan-src"

RUN set -eux \
    && apt-get update \
    # Requirments for the autogen.sh
    && apt-get install -y automake autoconf libtool pkg-config gettext perl python flex bison gperf \
    && cd "/strongswan-src" \
    && ./autogen.sh


FROM gcc:11.1.0 as strongswan-build

ARG STRONGSWAN_PREFIX
ARG STRONGSWAN_SYS_CONF_DIR
ARG STRONGSWAN_LIBEXEC_DIR
ARG STRONGSWAN_IPSEC_DIR
ARG STRONGSWAN_PID_DIR

ARG GCC_MARCH="silvermont"
ARG GCC_MTUNE="silvermont"

COPY --from=strongswan-configure "/strongswan-src" "/strongswan-src"

RUN set -eux \
    && apt-get update \
    # Enforce latest openssl version
    && apt-get install --upgrade -y libssl-dev \
    # Build requirements for StrongSwan
        bison flex gperf \
    && cd "/strongswan-src" \
    && export CFLAGS="-O2 -pipe -static -march=${GCC_MARCH} -mtune=${GCC_MTUNE}" \
    && export LDFLAGS="--static -pthread" \
    && ./configure \
        # Internal paths
        --prefix="${STRONGSWAN_PREFIX}" \
        --sysconfdir="${STRONGSWAN_SYS_CONF_DIR}" \
        --libexecdir="${STRONGSWAN_LIBEXEC_DIR}" \
        #--with-strongswan-conf=SYSCONFDIR/strongswan.conf \
        #--with-swanctldir=SYSCONFDIR/swanctl \
        #--with-resolv-conf=/etc/resolv.conf \
        --with-piddir="${STRONGSWAN_PID_DIR}" \
        --with-ipsecdir="${STRONGSWAN_IPSEC_DIR}" \
        #--libdir=PREFIX/lib \
        #--with-ipseclibdir=LIBDIR/ipsec \
        # For static compile
        --disable-shared --enable-static --enable-monolithic \
        # Reduce priviliges of the daemon; TODO validate option
        #--with-capabilities=native \
        # Disable all options and enable on demand; Crypto is based on OpenSSL and not in-tree
        --disable-defaults \
        # Enable default requirements
        --enable-charon --enable-ikev2 --enable-kernel-netlink --enable-nonce --enable-swanctl --enable-socket-default --enable-vici --enable-updown \
        # Enable certficiate and key handeling
        #--enable-attr --enable-pem --enable-pubkey --enable-revocation \
        #--enable-pgp --enable-pkcs1 --enable-pkcs7 --enable-pkcs8 --enable-pkcs12 \
        # Enable crl fetchers; Currently broken for static compile curl and openldap
        #--enable-curl --enable-ldap \
        #--enable-files \
        # OpenSSL for crypto; # TODO Validate aes-ni and sha-ni (At least the instructions are compiled in)
        --enable-openssl \
        #--enable-af-alg \
        # Enable security plugins
        --enable-addrblock --enable-duplicheck \
        # Enable EAP plugins \
        --enable-eap-radius \
        #--enable-eap-identity --enable-eap-dynamic \
        # Enable network plugins
        --enable-farp --enable-dhcp --enable-ha \
        # TODO Look into --enable-forecast: Might be required for WOL
        # TODO Look into --enable-connmark for correct connection setup
    && make -j "$(nproc)" install


# Not for crypto plugins
# Enable some crypto plugins
#--enable-aesni --enable-chapoly --enable-gcm --enable-sha3 \


FROM busybox:stable as folder-structure

ARG STRONGSWAN_PREFIX
ARG STRONGSWAN_SYS_CONF_DIR
ARG STRONGSWAN_IPSEC_DIR
ARG STRONGSWAN_PID_DIR
ARG ROOT_FOLDER_STRUCTURE

#COPY --from=strongswan-build /usr/lib/ipsec ${ROOT_FOLDER_STRUCTURE}/usr/lib/ipsec # Libs are not required in the image
COPY --from=strongswan-build "${STRONGSWAN_IPSEC_DIR}" "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_IPSEC_DIR}"
COPY --from=strongswan-build "${STRONGSWAN_PREFIX}/sbin/swanctl" "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_PREFIX}/sbin/swanctl"
COPY --from=strongswan-build "${STRONGSWAN_SYS_CONF_DIR}" "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_SYS_CONF_DIR}"

COPY "/entrypoint.sh" "${ROOT_FOLDER_STRUCTURE}/entrypoint.sh"

RUN set -eux \
    # Run dir for the the sockets
    && mkdir -p "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_PID_DIR}" \
#    && chown 20001:20001 "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_PID_DIR}" \
    # Utils that are likely required for basic scripting
    && mkdir -p "${ROOT_FOLDER_STRUCTURE}/bin" \
    && cp "/bin/sh" "${ROOT_FOLDER_STRUCTURE}/bin/sh" \
    && cp "/bin/sh" "${ROOT_FOLDER_STRUCTURE}/bin/sleep" \
    && cp "/bin/ip" "${ROOT_FOLDER_STRUCTURE}/bin/ip" \
    && cp "/bin/iproute" "${ROOT_FOLDER_STRUCTURE}/bin/iproute" \
    && cp "/bin/cat" "${ROOT_FOLDER_STRUCTURE}/bin/cat" \
    && cp "/bin/ls" "${ROOT_FOLDER_STRUCTURE}/bin/ls"

COPY "strongswan-config/charon-logging.conf" "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_SYS_CONF_DIR}/strongswan.d/charon-logging.conf"


FROM scratch

ARG STRONGSWAN_IPSEC_DIR
ARG ROOT_FOLDER_STRUCTURE
ENV PATH=/bin:/usr/sbin:/sbin:${STRONGSWAN_IPSEC_DIR}

COPY --from=folder-structure "${ROOT_FOLDER_STRUCTURE}" "/"

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD [ "swanctl", "--stats" ]
EXPOSE 500/udp
EXPOSE 4500/udp

#USER 20001:20001

ENTRYPOINT [ "/entrypoint.sh" ]
