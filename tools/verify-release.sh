#!/usr/bin/env bash
# Release gate for repo.cylo.net/openvpn:2.6.16-1. Run on the builder with the
# freshly built image as the only argument. Exits 0 only when every check
# passes and the registry confirms the tag does not exist yet.
set -uo pipefail

case "${1:-}" in
    repo.cylo.net/openvpn:2.6.16-1) EXPECTED_VERSION="2.6.16-1" ;;
    *) echo "Unsupported OpenVPN release candidate: ${1:-<none>}" >&2; exit 1 ;;
esac
NEW_IMAGE="$1"
# The 2.6.16 image this release replaces, pinned by digest.
BASELINE_IMAGE="repo.cylo.net/openvpn@sha256:a1d7a8637f1d3ebd698fdd57d388b5b124212a528fcde7b262ed9a90f74527a6"

for required_command in curl docker jq; do
    command -v "${required_command}" >/dev/null 2>&1 || { echo "Missing release-gate dependency: ${required_command}" >&2; exit 1; }
done

NONCE="$(date +%s)$$"
case "${NONCE}" in ''|*[!0-9]*) exit 1 ;; esac
P="openvpn-gate-${NONCE}"
REGISTRY_RESPONSE="$(mktemp /tmp/openvpn-registry-response.XXXXXX)"
failures=0

cleanup() {
    docker rm -f "${P}-old" "${P}-up" "${P}-fresh" >/dev/null 2>&1 || true
    docker volume rm "${P}-a-configs" "${P}-a-openvpn" "${P}-b-configs" "${P}-b-openvpn" >/dev/null 2>&1 || true
    rm -f "${REGISTRY_RESPONSE}"
}
trap cleanup EXIT INT TERM

http_code() { # container path [user:password]
    docker exec "$1" curl -s -o /dev/null -w '%{http_code}' ${3:+-u "$3"} "http://127.0.0.1$2"
}

expect() { # container path code [user:password]
    local who="${4:-none}" got
    who="${who%%:*}"
    got="$(http_code "$1" "$2" "${4:-}")"
    if [[ "${got}" == "$3" ]]; then
        echo "ok   ${who} $2 -> ${got}"
    else
        echo "FAIL ${who} $2 -> ${got} (want $3)"
        failures=$((failures + 1))
    fi
}

wait_ready() {
    local i
    for i in $(seq 1 180); do
        if docker exec "$1" test -f /configs/config.ovpn 2>/dev/null && [[ "$(http_code "$1" /config.ovpn)" == 401 ]]; then
            return 0
        fi
        sleep 2
    done
    echo "FAIL $1 did not become ready" >&2
    return 1
}

start() { # name volume-prefix image
    docker run -d --name "$1" --cap-add=NET_ADMIN \
        -e OPENVPN_USER=admin -e OPENVPN_PASSWORD=GateAdmin123 \
        -e DOMAIN=localhost -e EXTERNAL_PORT=1194 -e VIRTUAL_HOST=localhost \
        -e INSTANCE_ID=gate -e SKIP_APPBOX_CALLBACK=1 \
        -v "$2-configs:/configs" -v "$2-openvpn:/etc/openvpn" "$3" >/dev/null
}

echo "== baseline 2.6.16: a second login can read the owner profile"
docker pull -q "${BASELINE_IMAGE}" >/dev/null || { echo "Cannot pull baseline image" >&2; exit 1; }
start "${P}-old" "${P}-a" "${BASELINE_IMAGE}" && wait_ready "${P}-old" || exit 1
docker exec "${P}-old" /scripts/adduser.sh alice GateAlice123 >/dev/null 2>&1
expect "${P}-old" /config.ovpn 200 alice:GateAlice123
docker rm -f "${P}-old" >/dev/null

echo "== upgrade from 2.6.16 volumes"
start "${P}-up" "${P}-a" "${NEW_IMAGE}" && wait_ready "${P}-up" || exit 1
expect "${P}-up" /config.ovpn 401
expect "${P}-up" /config.ovpn 401 admin:wrong
expect "${P}-up" /config.ovpn 200 admin:GateAdmin123
expect "${P}-up" /alice.ovpn 404 admin:GateAdmin123
expect "${P}-up" /alice.ovpn 200 alice:GateAlice123
expect "${P}-up" /config.ovpn 404 alice:GateAlice123
expect "${P}-up" /admin.ovpn 404 alice:GateAlice123
expect "${P}-up" / 404 alice:GateAlice123
docker exec "${P}-up" /moduser.sh GateAdmin456 >/dev/null 2>&1
expect "${P}-up" /config.ovpn 200 admin:GateAdmin456
expect "${P}-up" /admin.ovpn 200 admin:GateAdmin456
docker exec "${P}-up" /scripts/deluser.sh alice >/dev/null 2>&1
expect "${P}-up" /alice.ovpn 401 alice:GateAlice123

echo "== restart"
docker restart "${P}-up" >/dev/null && wait_ready "${P}-up" || exit 1
expect "${P}-up" /config.ovpn 200 admin:GateAdmin456
for process in "openvpn --config" "nginx: master"; do
    if docker exec "${P}-up" pgrep -f "${process}" >/dev/null; then
        echo "ok   process running: ${process}"
    else
        echo "FAIL process not running: ${process}"
        failures=$((failures + 1))
    fi
done

echo "== fresh install"
start "${P}-fresh" "${P}-b" "${NEW_IMAGE}" && wait_ready "${P}-fresh" || exit 1
docker exec "${P}-fresh" /scripts/adduser.sh bob GateBob123 >/dev/null 2>&1
expect "${P}-fresh" /config.ovpn 200 admin:GateAdmin123
expect "${P}-fresh" /bob.ovpn 200 bob:GateBob123
expect "${P}-fresh" /config.ovpn 404 bob:GateBob123
if [[ "$(docker exec "${P}-fresh" grep -c -- '-----BEGIN' /configs/bob.ovpn)" == 4 ]]; then
    echo "ok   bob.ovpn has key, cert, ca and tls-auth blocks"
else
    echo "FAIL bob.ovpn is incomplete"
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    echo "${failures} check(s) failed; refusing publication" >&2
    exit 1
fi

echo "== registry"
docker_config="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
registry_auth="$(jq -er '(.auths["repo.cylo.net"].auth // .auths["https://repo.cylo.net"].auth // empty)' "${docker_config}" 2>/dev/null)" || {
    echo "Authenticated registry credentials unavailable; refusing publication" >&2
    exit 1
}
if ! registry_status="$(printf 'header = "Authorization: Basic %s"\n' "${registry_auth}" |
    curl --config - --silent --show-error --connect-timeout 10 --max-time 60 \
        --output "${REGISTRY_RESPONSE}" --write-out '%{http_code}' \
        --header 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json' \
        "https://repo.cylo.net/v2/openvpn/manifests/${EXPECTED_VERSION}")"; then
    echo "Registry request failed; tag state is indeterminate" >&2
    exit 1
fi
unset registry_auth
if [[ "${registry_status}" == 404 ]] &&
    jq -e '.errors | type == "array" and any(.[]; .code == "MANIFEST_UNKNOWN")' "${REGISTRY_RESPONSE}" >/dev/null; then
    echo "Registry confirms ${NEW_IMAGE} is absent"
elif [[ "${registry_status}" == 200 ]]; then
    echo "Refusing to overwrite ${NEW_IMAGE}" >&2
    exit 1
else
    echo "Registry HTTP ${registry_status}; tag absence not proven" >&2
    exit 1
fi

echo "Release gate passed for ${NEW_IMAGE}"
