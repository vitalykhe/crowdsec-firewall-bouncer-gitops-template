#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
chart="$repo_root/charts/crowdsec-firewall-bouncer"
iptables_values="$chart/ci/iptables-values.yaml"
nftables_values="$chart/ci/nftables-values.yaml"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  file=$1
  text=$2
  description=$3
  grep -F -- "$text" "$file" >/dev/null || fail "$description"
}

assert_not_contains() {
  file=$1
  text=$2
  description=$3
  if grep -F -- "$text" "$file" >/dev/null; then
    fail "$description"
  fi
}

expect_render_failure() {
  name=$1
  expected=$2
  shift 2
  if helm template test "$chart" --namespace crowdsec -f "$iptables_values" "$@" >"$tmp_dir/$name.out" 2>"$tmp_dir/$name.err"; then
    fail "$name unexpectedly rendered successfully"
  fi
  assert_contains "$tmp_dir/$name.err" "$expected" "$name did not mention $expected"
}

# Required trust and environment inputs must fail before Kubernetes sees them.
expect_render_failure missing-image-repository /image/repository --set-string image.repository=
expect_render_failure malformed-image-digest /image/digest --set-string image.digest=sha256:bad
expect_render_failure missing-secret /existingSecret/name --set-string existingSecret.name=
expect_render_failure missing-api-url /config/apiUrl --set-string config.apiUrl=
expect_render_failure invalid-backend /config/backend --set-string config.backend=pf
expect_render_failure empty-iptables-chains /config/iptables --set-json config.iptables.chains=[]
expect_render_failure disabled-nftables-families /config/nftables \
  --set-string config.backend=nftables \
  --set config.nftables.ipv4.enabled=false \
  --set config.nftables.ipv6.enabled=false

helm lint --strict "$chart" -f "$iptables_values" >"$tmp_dir/lint.out"
helm template test "$chart" --namespace crowdsec -f "$iptables_values" >"$tmp_dir/iptables.yaml"
helm template test "$chart" --namespace crowdsec -f "$nftables_values" >"$tmp_dir/nftables.yaml"
helm template test "$chart" --namespace crowdsec -f "$iptables_values" \
  --set metrics.serviceMonitor.enabled=true >"$tmp_dir/servicemonitor.yaml"
helm template test "$chart" --namespace crowdsec -f "$iptables_values" \
  --set metrics.enabled=false >"$tmp_dir/metrics-disabled.yaml"
helm template test "$chart" --namespace crowdsec -f "$iptables_values" \
  --set-string config.denyAction=REJECT >"$tmp_dir/reject.yaml"

expected_image='image: "registry.example.com/security/crowdsec-firewall-bouncer@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
assert_contains "$tmp_dir/iptables.yaml" "$expected_image" "image is not rendered by immutable digest"
assert_not_contains "$tmp_dir/iptables.yaml" 'initContainers:' "runtime installer init container is still rendered"
assert_not_contains "$tmp_dir/iptables.yaml" 'privileged: true' "privileged mode is still rendered"
assert_not_contains "$tmp_dir/iptables.yaml" 'kind: ClusterRole' "unused Kubernetes API RBAC is still rendered"
assert_not_contains "$tmp_dir/iptables.yaml" 'kind: Secret' "chart still renders an inline Secret"
assert_contains "$tmp_dir/iptables.yaml" 'automountServiceAccountToken: false' "service-account token is not disabled"
assert_contains "$tmp_dir/iptables.yaml" 'readOnlyRootFilesystem: true' "root filesystem is not read-only"
assert_contains "$tmp_dir/iptables.yaml" 'runAsNonRoot: true' "container is not required to run as non-root"
assert_contains "$tmp_dir/iptables.yaml" 'allowPrivilegeEscalation: false' "privilege escalation is not disabled"
assert_contains "$tmp_dir/iptables.yaml" '          - NET_ADMIN' "NET_ADMIN is not granted"
assert_contains "$tmp_dir/iptables.yaml" '          - NET_RAW' "NET_RAW is not granted"
assert_contains "$tmp_dir/iptables.yaml" 'log_mode: stdout' "logs are not sent to stdout"
assert_contains "$tmp_dir/iptables.yaml" 'api_key: ${API_KEY}' "ConfigMap no longer defers API key expansion to the process"
assert_contains "$tmp_dir/iptables.yaml" 'mode: iptables' "iptables mode is not rendered"
assert_contains "$tmp_dir/iptables.yaml" 'iptables_chains:' "iptables chains are not rendered"
assert_not_contains "$tmp_dir/iptables.yaml" '    nftables:' "nftables settings leaked into iptables configuration"
assert_contains "$tmp_dir/nftables.yaml" 'mode: nftables' "nftables mode is not rendered"
assert_contains "$tmp_dir/nftables.yaml" '    nftables:' "nftables settings are not rendered"
assert_not_contains "$tmp_dir/nftables.yaml" 'iptables_chains:' "iptables settings leaked into nftables configuration"
assert_contains "$tmp_dir/iptables.yaml" 'checksum/config:' "ConfigMap checksum annotation is missing"
assert_contains "$tmp_dir/iptables.yaml" 'startupProbe:' "startup probe is missing"
assert_contains "$tmp_dir/iptables.yaml" 'readinessProbe:' "readiness probe is missing"
assert_contains "$tmp_dir/iptables.yaml" 'livenessProbe:' "liveness probe is missing"
assert_contains "$tmp_dir/iptables.yaml" 'kind: Service' "metrics Service is missing"
assert_not_contains "$tmp_dir/iptables.yaml" 'kind: ServiceMonitor' "ServiceMonitor rendered without opt-in"
assert_contains "$tmp_dir/servicemonitor.yaml" 'kind: ServiceMonitor' "ServiceMonitor did not render when enabled"
assert_not_contains "$tmp_dir/metrics-disabled.yaml" 'startupProbe:' "startup probe rendered while metrics are disabled"
assert_not_contains "$tmp_dir/metrics-disabled.yaml" 'readinessProbe:' "readiness probe rendered while metrics are disabled"
assert_not_contains "$tmp_dir/metrics-disabled.yaml" 'livenessProbe:' "liveness probe rendered while metrics are disabled"
assert_not_contains "$tmp_dir/metrics-disabled.yaml" 'kind: ServiceMonitor' "ServiceMonitor rendered while metrics are disabled"

api_key_env_count=$(grep -c 'name: API_KEY' "$tmp_dir/iptables.yaml" || true)
[ "$api_key_env_count" -eq 1 ] || fail "API_KEY must be exposed to exactly one container"

checksum_default=$(awk '/checksum\/config:/ {gsub(/"/, "", $2); print $2; exit}' "$tmp_dir/iptables.yaml")
checksum_reject=$(awk '/checksum\/config:/ {gsub(/"/, "", $2); print $2; exit}' "$tmp_dir/reject.yaml")
[ -n "$checksum_default" ] || fail "default ConfigMap checksum is empty"
[ -n "$checksum_reject" ] || fail "changed ConfigMap checksum is empty"
[ "$checksum_default" != "$checksum_reject" ] || fail "ConfigMap checksum does not change with configuration"

printf 'PASS: chart behavior and security invariants\n'
