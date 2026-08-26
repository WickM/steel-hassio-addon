# check=skip=SecretsUsedInArgOrEnv

# ---------------------------------------------------------------------------
# Steel Browser as a hassio add-on
# ---------------------------------------------------------------------------
# We wrap the official steel-browser image (`ghcr.io/steel-dev/steel-browser`,
# Apache 2.0) with:
#   - s6-overlay v3 + bashio for addon lifecycle (start/stop/log)
#   - tempio for config templating
#   - persistent profile volume mount via the `map: share:rw` addon flag
#
# Why wrap instead of running the upstream image directly?
#   - hassio addons require s6 supervision so HA can restart them cleanly.
#   - The addon needs a stable entrypoint that honors HA options.json.
#   - We want addon-native logging and health endpoints.
#
# We do NOT install steel's source / build it ourselves — that'd duplicate
# ~600 MB of Chromium + Node + Vite UI build for zero gain. The official
# image is multi-arch (linux/amd64, linux/arm64) and maintained upstream.
# ---------------------------------------------------------------------------

FROM ghcr.io/steel-dev/steel-browser:latest

ENV \
    LANG=C.UTF-8 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_CMD_WAIT_FOR_SERVICES=1 \
    S6_VERBOSITY=0 \
    # Steel defaults — overridden by /etc/cont-init.d/10-config from HA options.
    NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    CDP_REDIRECT_PORT=9223 \
    # Profile dir lives on the persistent /share/steel volume (map: share:rw).
    # Steel's session manager writes cookies + localStorage + IndexedDB here.
    # If you change this, also update config.yaml `options.data_path`.
    STEEL_DATA_PATH=/share/steel

# Shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Addon base configuration (s6-overlay, bashio, tempio)
ARG BUILD_ARCH=amd64
# renovate: datasource=github-releases packageName=hassio-addons/bashio
ARG BASHIO_VERSION="v0.18.1"
# renovate: datasource=github-releases packageName=just-containers/s6-overlay versioning=regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)\.(?<other>\d+)$
ARG S6_OVERLAY_VERSION="3.2.1.0"
# renovate: datasource=github-releases packageName=home-assistant/tempio
ARG TEMPIO_VERSION="2024.11.2"

RUN \
    apt-get update && apt-get install -y --no-install-recommends \
        bash \
        curl \
        ca-certificates \
        jq \
        tzdata \
        tar \
        xz-utils \
        # Steel's bundled chromium needs these for headless rendering;
        # upstream image already has most but be defensive.
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2 \
    \
    && S6_ARCH="${BUILD_ARCH}" \
    && if [ "${BUILD_ARCH}" = "amd64" ]; then S6_ARCH="x86_64"; fi \
    \
    && curl -L -s "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        | tar -C / -Jxpf - \
    && curl -L -s "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
        | tar -C / -Jxpf - \
    && curl -L -s "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz" \
        | tar -C / -Jxpf - \
    && curl -L -s "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz" \
        | tar -C / -Jxpf - \
    \
    && curl -J -L -o /tmp/bashio.tar.gz \
        "https://github.com/hassio-addons/bashio/archive/${BASHIO_VERSION}.tar.gz" \
    && mkdir -p /tmp/bashio-extract /usr/lib/bashio \
    && tar zxvf /tmp/bashio.tar.gz --strip 1 -C /tmp/bashio-extract \
    && mv /tmp/bashio-extract/lib /usr/lib/bashio/lib \
    && ln -sf /usr/lib/bashio/lib/bashio /usr/bin/bashio \
    \
    && curl -L -s -o /usr/bin/tempio \
        "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}" \
    && chmod a+x /usr/bin/tempio \
    \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/* /tmp/*

COPY rootfs /

ENTRYPOINT ["/init"]
CMD []

ARG BUILD_VERSION \
    BUILD_DATE \
    BUILD_DESCRIPTION \
    BUILD_NAME \
    BUILD_REF \
    BUILD_REPOSITORY

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="Manuel <https://github.com/WickM>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Steel Hass.io Add-on" \
    org.opencontainers.image.authors="Manuel <https://github.com/WickM>" \
    org.opencontainers.image.licenses="Apache-2.0" \
    org.opencontainers.image.url="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"
