ARG STRONGSWAN_PREFIX="/usr"
ARG STRONGSWAN_SYS_CONF_DIR="/etc/strongswan"
ARG STRONGSWAN_LIBEXEC_DIR="/usr/libexec"
ARG STRONGSWAN_IPSEC_DIR="/usr/libexec/ipsec"
ARG STRONGSWAN_PID_DIR="/var/run"

ARG ROOT_FOLDER_STRUCTURE="/strongswan"



FROM gcc:11.2.0 as strongswan-configure

COPY strongswan "/strongswan-src"

# hadolint ignore=DL3003,DL3008
RUN set -eux \
    && apt-get update \
    # Requirments for the autogen.sh
    && apt-get install --no-install-recommends -y automake autoconf libtool pkg-config gettext perl python flex bison gperf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && cd "/strongswan-src" \
    && ./autogen.sh


FROM alpine:3.15.0 as strongswan-build

ARG TARGETPLATFORM

ARG STRONGSWAN_PREFIX
ARG STRONGSWAN_SYS_CONF_DIR
ARG STRONGSWAN_LIBEXEC_DIR
ARG STRONGSWAN_IPSEC_DIR
ARG STRONGSWAN_PID_DIR


ARG GCC_OPTIMIZE_AMD64_FLAGS="-march=silvermont -mtune=generic"
# Info for ARM gcc flags https://gist.github.com/fm4dd/c663217935dc17f0fc73c9c81b0aa845; Currently issues with some flags as they are not recognized by the compiler
# Flags are based on the RPi2
#ARG GCC_OPTIMIZE_ARMV7_FLAGS="-mcpu=cortex-a7 -mfloat-abi=hard -mfpu=neon-vfpv4"
ARG GCC_OPTIMIZE_ARMV7_FLAGS="-mcpu=cortex-a7"
# Flags are based on the RPi3. The crypto extension are enabled
#ARG GCC_OPTIMIZE_ARMV8_FLAGS="-mcpu=cortex-a53+crypto -mfloat-abi=hard -mfpu=neon-fp-armv8 -mneon-for-64bits"
ARG GCC_OPTIMIZE_ARMV8_FLAGS="-mcpu=cortex-a53+crypto"

COPY --from=strongswan-configure "/strongswan-src" "/strongswan-src"

# hadolint ignore=DL3003,DL3018
RUN set -eux \
    && apk add --no-cache \
        # Alpine basic compile packages
        build-base musl-dev \
        # Alpine libssl (OpenSSL)
        openssl-dev openssl-libs-static \
        # Basic build requirements for StrongSwan (same as on Debian)
        bison flex gperf \
        # Additional packages on Alpine
        linux-headers python3 gmp-dev gettext-dev automake autoconf libtool \
        # Curl dependencies to fetch CRLs via HTTP
        curl-dev curl-static nghttp2-dev nghttp2-static zlib-dev zlib-static brotli-dev brotli-static \
    && cd "/strongswan-src" \
    # For libcurl $(pkg-config --libs --static libcurl) is not working due to broken brotli references https://github.com/google/brotli/issues/795
    # For Alpine < 3.14 use the following:
    #&& LIBCURL_WORKAROUND_LIBS="-lcurl -lnghttp2 -lssl -lcrypto -lssl -lcrypto -lbrotlidec-static -lbrotlicommon-static -lz" \
    # For Alpine >= 3.14 use the following:
    && LIBCURL_WORKAROUND_LIBS="-lcurl -lnghttp2 -lssl -lcrypto -lssl -lcrypto -lbrotlidec -lbrotlicommon -lz" \
        && export LIBS="-L/usr/lib/** -L/lib/** -L/usr/include/** ${LIBCURL_WORKAROUND_LIBS}" \
    && CFLAGS_SECURITY="-fPIE -fstack-protector-strong -Wstack-protector --param ssp-buffer-size=4 -fstack-clash-protection -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security" \
        && if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
                export GCC_CPU_OPTIMIZE_FLAGS="${GCC_OPTIMIZE_AMD64_FLAGS}"; \
            elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then \
                export GCC_CPU_OPTIMIZE_FLAGS="${GCC_OPTIMIZE_ARMV7_FLAGS}"; \
            elif [ "$TARGETPLATFORM" = "linux/arm/v8" ] || [ "$TARGETPLATFORM" = "linux/arm64" ] || [ "$TARGETPLATFORM" = "linux/arm64/v8" ]; then \
                export GCC_CPU_OPTIMIZE_FLAGS="${GCC_OPTIMIZE_ARMV8_FLAGS}"; \
            else \
                export GCC_CPU_OPTIMIZE_FLAGS=""; \
            fi \
        && export CFLAGS="-O2 -pipe -static ${GCC_CPU_OPTIMIZE_FLAGS} ${CFLAGS_SECURITY}" \
    && LDFLAGS_SECURITY="-Wl,-z,relro -Wl,-z,now" \ 
        && export LDFLAGS="--static -pthread -Bstatic ${LDFLAGS_SECURITY}" \
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
        #--libdir="${STRONGSWAN_LIB_DIR}" \
        #--with-ipseclibdir="${STRONGSWAN_IPSEC_LIB_DIR}" \
        # For static compile
        --disable-shared --enable-static --enable-monolithic \
        # Reduce priviliges of the daemon; TODO validate option
        #--with-capabilities=native \
        # Disable all options and enable on demand; Crypto is based on OpenSSL and not in-tree
        --disable-defaults \
        # Enable default requirements
        --enable-attr --enable-charon --enable-ikev2 --enable-kernel-netlink --enable-nonce --enable-swanctl --enable-socket-default --enable-updown --enable-vici \
        # OpenSSL for crypto & certficiate and key handeling; # TODO Validate aes-ni and sha-ni (At least the instructions are compiled in)
        --enable-openssl --enable-pem \
        # Enable CRL fetching plugins; LDAP compilation is a pain for now; '--enable-files' not required as provided by curl as well
        --enable-curl \
        # Enable security plugins
        --enable-addrblock --enable-duplicheck \
        # Enable EAP plugins \
        --enable-eap-radius --enable-eap-identity --enable-radattr \
        #--enable-eap-identity --enable-eap-dynamic \
        # Enable network plugins
        --enable-farp --enable-dhcp \
        # Test vectors for crypto; Disable for now as it tests every vector on every swanctl command (e.g. healthcheck) \
        #--enable-test-vectors \
        # HA is not enabled for now as it requires a patched kernel
        #--enable-ha \
        # TODO Look into --enable-forecast: Might be required for WOL
        # TODO Look into --enable-connmark for correct connection setup
        || cat config.log \
    && make -j "$(nproc)" install



FROM busybox:stable-musl as folder-structure

ARG STRONGSWAN_PREFIX
ARG STRONGSWAN_SYS_CONF_DIR
ARG STRONGSWAN_IPSEC_DIR
ARG STRONGSWAN_PID_DIR
ARG ROOT_FOLDER_STRUCTURE

#COPY --from=strongswan-build /usr/lib/ipsec ${ROOT_FOLDER_STRUCTURE}/usr/lib/ipsec # Libs are not required in the image
#COPY --from=strongswan-build "${STRONGSWAN_IPSEC_LIB_DIR}" "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_IPSEC_DIR}"
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
    && cp "/bin/sleep" "${ROOT_FOLDER_STRUCTURE}/bin/sleep" \
    && cp "/bin/ip" "${ROOT_FOLDER_STRUCTURE}/bin/ip" \
    && cp "/bin/iproute" "${ROOT_FOLDER_STRUCTURE}/bin/iproute" \
    && cp "/bin/cat" "${ROOT_FOLDER_STRUCTURE}/bin/cat" \
    && cp "/bin/ls" "${ROOT_FOLDER_STRUCTURE}/bin/ls"

COPY "strongswan-config/strongswan.d" "${ROOT_FOLDER_STRUCTURE}/${STRONGSWAN_SYS_CONF_DIR}/strongswan.d"


FROM scratch

ARG STRONGSWAN_IPSEC_DIR
ARG ROOT_FOLDER_STRUCTURE
ENV PATH=/bin:/usr/sbin:/sbin:${STRONGSWAN_IPSEC_DIR}

COPY --from=folder-structure "${ROOT_FOLDER_STRUCTURE}" "/"

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD "swanctl" "--stats"
EXPOSE 500/udp \
    4500/udp

#USER 20001:20001

ENTRYPOINT [ "/entrypoint.sh" ]
