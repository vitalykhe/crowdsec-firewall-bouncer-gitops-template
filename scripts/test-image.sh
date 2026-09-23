#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  printf 'usage: %s IMAGE\n' "$0" >&2
  exit 2
fi

image=$1

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

docker info >/dev/null 2>&1 || fail "Docker daemon is unavailable"
docker image inspect "$image" >/dev/null 2>&1 || fail "image does not exist: $image"

configured_user=$(docker image inspect --format '{{.Config.User}}' "$image")
[ "$configured_user" = "65532:65532" ] || fail "image user must be 65532:65532, got $configured_user"

version_output=$(docker run --rm --entrypoint /usr/local/bin/crowdsec-firewall-bouncer "$image" -V)
printf '%s\n' "$version_output" | grep -F 'v0.0.34' >/dev/null || fail "bouncer version is not v0.0.34"

docker run --rm --entrypoint /bin/sh "$image" -ec '
  command -v iptables >/dev/null
  command -v ip6tables >/dev/null
  command -v ipset >/dev/null
  command -v nft >/dev/null
' || fail "one or more firewall tools are missing from PATH"

default_env=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$image")
if printf '%s\n' "$default_env" | grep -E '^API_(KEY|URL)=' >/dev/null; then
  fail "image must not define a default API key or LAPI URL"
fi

printf 'PASS: reference image contract\n'
