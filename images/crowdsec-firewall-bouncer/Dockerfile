# syntax=docker/dockerfile:1.7

ARG DEBIAN_IMAGE=debian:12-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

FROM ${DEBIAN_IMAGE} AS downloader

ARG TARGETARCH
ARG BOUNCER_VERSION=v0.0.34

COPY checksums.txt /tmp/checksums.txt

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64|arm64) ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    artifact="crowdsec-firewall-bouncer-linux-${TARGETARCH}.tgz"; \
    checksum_count="$(awk -v version="$BOUNCER_VERSION" -v arch="$TARGETARCH" '$1 == version && $2 == arch {count++} END {print count+0}' /tmp/checksums.txt)"; \
    [ "$checksum_count" -eq 1 ]; \
    expected="$(awk -v version="$BOUNCER_VERSION" -v arch="$TARGETARCH" '$1 == version && $2 == arch {print $3}' /tmp/checksums.txt)"; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl; \
    curl --fail --silent --show-error --location \
      --output "/tmp/${artifact}" \
      "https://github.com/crowdsecurity/cs-firewall-bouncer/releases/download/${BOUNCER_VERSION}/${artifact}"; \
    printf '%s  %s\n' "$expected" "/tmp/${artifact}" | sha256sum --check --strict -; \
    mkdir -p /tmp/extracted /out; \
    tar -xzf "/tmp/${artifact}" -C /tmp/extracted; \
    binary_count="$(find /tmp/extracted -type f -name crowdsec-firewall-bouncer | wc -l | tr -d ' ')"; \
    [ "$binary_count" -eq 1 ]; \
    binary="$(find /tmp/extracted -type f -name crowdsec-firewall-bouncer)"; \
    install -m 0755 "$binary" /out/crowdsec-firewall-bouncer

FROM ${DEBIAN_IMAGE} AS runtime

ARG BOUNCER_VERSION=v0.0.34

LABEL org.opencontainers.image.title="CrowdSec Firewall Bouncer reference runtime" \
      org.opencontainers.image.description="Source-first BYOI reference image; build and publish it in your own trusted pipeline" \
      org.opencontainers.image.source="https://github.com/vitalykhe/security-charts" \
      org.opencontainers.image.version="${BOUNCER_VERSION}" \
      org.opencontainers.image.licenses="MIT"

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      ipset \
      iptables \
      nftables; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/cache/debconf/*

COPY --from=downloader --chown=65532:65532 /out/crowdsec-firewall-bouncer /usr/local/bin/crowdsec-firewall-bouncer

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

USER 65532:65532

ENTRYPOINT ["/usr/local/bin/crowdsec-firewall-bouncer"]
CMD ["-c", "/config/crowdsec-firewall-bouncer.yaml"]
