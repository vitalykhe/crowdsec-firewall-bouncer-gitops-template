# CrowdSec Firewall Bouncer reference image

This directory is source code for an operator-built image. The
`security-charts` project does **not** publish a runtime image and does not make
the image trust decision for you.

The reference build downloads the official CrowdSec Firewall Bouncer release,
checks its SHA256, and combines it with the firewall tools required by the Helm
chart. Review the Dockerfile and checksum through your organization's software
intake process before building it.

## Trust boundary

The recorded checksum detects a release artifact whose bytes change after the
checksum was recorded. It does not authenticate the first observation of that
checksum. The v0.0.34 values in `checksums.txt` match the digests exposed by the
GitHub release API on 2026-09-10.

The Debian base is pinned to a multi-architecture manifest digest. Debian
package repositories can still serve newer patched package revisions during a
later build, so the digest of your completed image is the deployment identity.

You own:

- review of the upstream release and these build inputs;
- vulnerability scanning and policy enforcement;
- publication to your registry;
- signing and provenance, if required by your organization;
- recording and updating the final image digest in GitOps.

## Build and test one architecture

From the repository root:

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  --tag registry.example.com/security/crowdsec-firewall-bouncer:v0.0.34-1 \
  images/crowdsec-firewall-bouncer

sh scripts/test-image.sh \
  registry.example.com/security/crowdsec-firewall-bouncer:v0.0.34-1
```

Use `linux/arm64` instead when building natively for arm64.

## Scan, publish, and capture the digest

Run your organization's scanner before publishing. For example, if Trivy is
already part of your trusted toolchain:

```bash
trivy image --exit-code 1 --severity CRITICAL,HIGH \
  registry.example.com/security/crowdsec-firewall-bouncer:v0.0.34-1
```

Build and push both supported architectures:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag registry.example.com/security/crowdsec-firewall-bouncer:v0.0.34-1 \
  --push \
  images/crowdsec-firewall-bouncer

docker buildx imagetools inspect \
  registry.example.com/security/crowdsec-firewall-bouncer:v0.0.34-1
```

Copy the `Digest: sha256:...` value into the consuming GitOps repository:

```yaml
image:
  repository: registry.example.com/security/crowdsec-firewall-bouncer
  digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Do not deploy using the human-readable tag. The Helm chart always renders the
repository together with the immutable digest.

If your organization signs images, sign the digest rather than a mutable tag
and enforce verification in the target cluster with your admission policy.

## Runtime contract

A replacement image is compatible when it:

- provides `/usr/local/bin/crowdsec-firewall-bouncer` v0.0.34;
- provides `iptables`, `ip6tables`, `ipset`, and `nft` in `PATH`;
- accepts `-c /config/crowdsec-firewall-bouncer.yaml`;
- supports numeric UID/GID 65532 and a read-only root filesystem;
- works with only `NET_ADMIN` and `NET_RAW` added capabilities;
- does not contain an API key or environment-specific LAPI URL.

The chart supplies writable `/run` and `/tmp` volumes. Kernel modules must be
available on the node; the container does not receive `SYS_MODULE` and does not
run `modprobe`.

## Updating CrowdSec Firewall Bouncer

For a new upstream release:

1. Review the upstream changelog and release provenance.
2. Record the official release digests for amd64 and arm64 in
   `checksums.txt`.
3. Update `BOUNCER_VERSION`, the chart `appVersion`, and the image-contract
   test together.
4. Build and test both architectures.
5. Exercise iptables and nftables in a staging cluster before updating the
   production image digest.
