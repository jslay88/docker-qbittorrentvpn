#!/bin/bash
# Opt-in Proton-style NAT-PMP. Started only when NATPMP_ENABLED is set.

log() {
	echo "$1" | ts '%Y-%m-%d %H:%M:%.S'
}

discover_gateway() {
	if [[ -n "${NATPMP_GATEWAY:-}" ]]; then
		printf '%s\n' "${NATPMP_GATEWAY}"
		return 0
	fi

	local conf="${VPN_CONFIG:-/config/wireguard/wg0.conf}"
	if [[ ! -f "${conf}" ]]; then
		return 1
	fi

	local address ip
	address=$(awk '
		/^\[/ { in_iface = ($0 ~ /^\[Interface\]/) }
		in_iface && /^[Aa]ddress[[:space:]]*=/ {
			line = $0
			sub(/^[^=]*=[[:space:]]*/, "", line)
			print line
			exit
		}
	' "${conf}")
	ip=$(printf '%s\n' "${address}" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
	if [[ -z "${ip}" ]]; then
		return 1
	fi

	# Proton gives the client a /32 (10.2.0.2/32). The NAT-PMP gateway is .1.
	printf '%s\n' "${ip%.*}.1"
}

mapped_port() {
	printf '%s\n' "$1" | grep -oE 'Mapped public port [0-9]+' | awk '{print $4; exit}'
}

webui_base() {
	local conf="/config/qBittorrent/config/qBittorrent.conf"
	local port="8080"
	local scheme="http"
	local configured

	if [[ -f "${conf}" ]]; then
		configured=$(awk -F= '/^WebUI\\Port=/ {print $2; exit}' "${conf}")
		if [[ -n "${configured}" ]]; then
			port="${configured}"
		fi
		if awk -F= '/^WebUI\\HTTPS\\Enabled=/ {print $2; exit}' "${conf}" | grep -qx 'true'; then
			scheme="https"
		fi
	fi
	printf '%s\n' "${scheme}://127.0.0.1:${port}"
}

update_listen_port() {
	local port="$1"
	local base
	base=$(webui_base)
	curl -kfsS -X POST "${base}/api/v2/app/setPreferences" \
		--data-urlencode "json={\"listen_port\":${port},\"random_port\":false,\"upnp\":false}" \
		>/dev/null
}

if [[ "${1:-}" == "--print-gateway" ]]; then
	discover_gateway
	exit $?
fi

lifetime="${NATPMP_LIFETIME:-60}"
interval="${NATPMP_INTERVAL:-45}"
current_port=""

log "[INFO] NAT-PMP loop started. Lifetime ${lifetime}s, renew every ${interval}s."

while true; do
	gateway=$(discover_gateway) || {
		log "[ERROR] Could not find a NAT-PMP gateway. Set NATPMP_GATEWAY or check wg0.conf."
		sleep "${interval}"
		continue
	}

	udp_out=$(natpmpc -a 1 0 udp "${lifetime}" -g "${gateway}" 2>&1) || {
		log "[ERROR] UDP NAT-PMP request to ${gateway} failed."
		log "${udp_out}"
		sleep "${interval}"
		continue
	}
	tcp_out=$(natpmpc -a 1 0 tcp "${lifetime}" -g "${gateway}" 2>&1) || {
		log "[ERROR] TCP NAT-PMP request to ${gateway} failed."
		log "${tcp_out}"
		sleep "${interval}"
		continue
	}

	udp_port=$(mapped_port "${udp_out}")
	tcp_port=$(mapped_port "${tcp_out}")
	if [[ -z "${udp_port}" || -z "${tcp_port}" || "${udp_port}" != "${tcp_port}" ]]; then
		log "[ERROR] NAT-PMP ports disagree (udp=${udp_port:-none} tcp=${tcp_port:-none}). Keeping ${current_port:-unset}."
		sleep "${interval}"
		continue
	fi

	if [[ "${udp_port}" != "${current_port}" ]]; then
		if update_listen_port "${udp_port}"; then
			current_port="${udp_port}"
			log "[INFO] qBittorrent listen port set to ${current_port}."
		else
			log "[ERROR] Failed to set qBittorrent listen port to ${udp_port}."
		fi
	fi

	sleep "${interval}"
done
