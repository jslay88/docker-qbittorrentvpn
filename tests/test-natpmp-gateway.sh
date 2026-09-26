#!/bin/bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="${root}/qbittorrent/natpmp.sh"
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT

cat > "${tmp}" <<'EOF'
[Interface]
PrivateKey = abcdef
Address = 10.2.0.2/32

[Peer]
PublicKey = abcdef
Endpoint = example.com:51820
AllowedIPs = 0.0.0.0/0
EOF

got=$(VPN_CONFIG="${tmp}" bash "${script}" --print-gateway)
if [[ "${got}" != "10.2.0.1" ]]; then
	echo "expected 10.2.0.1 from /32 address, got '${got}'" >&2
	exit 1
fi

cat > "${tmp}" <<'EOF'
[Interface]
Address = 10.2.0.2/32, fd7a:115c:a1e0::2/128
EOF

got=$(VPN_CONFIG="${tmp}" bash "${script}" --print-gateway)
if [[ "${got}" != "10.2.0.1" ]]; then
	echo "expected 10.2.0.1 from dual-stack address, got '${got}'" >&2
	exit 1
fi

got=$(NATPMP_GATEWAY=10.9.9.9 VPN_CONFIG="${tmp}" bash "${script}" --print-gateway)
if [[ "${got}" != "10.9.9.9" ]]; then
	echo "expected NATPMP_GATEWAY override, got '${got}'" >&2
	exit 1
fi

echo "natpmp gateway parser ok"
