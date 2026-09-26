# qBittorrent, WireGuard and OpenVPN

Modified fork of [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn). Alpine base, qBittorrent and libtorrent compiled from source, WireGuard or OpenVPN, and an iptables killswitch.

Images are published to `ghcr.io/jslay88/docker-qbittorrentvpn`. Tags are the qBittorrent version (`5.2.3`) and `latest`. A daily check rebuilds when qBittorrent, libtorrent 2.0, or `alpine:3` changes. A failed build or WebUI smoke test does not replace the existing tag.

GPL-3.0. Credits: [MarkusMcNugen/docker-qBittorrentvpn](https://github.com/MarkusMcNugen/docker-qBittorrentvpn), [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn).

## Run

```bash
docker run -d \
  -v /your/config/path/:/config \
  -v /your/downloads/path/:/downloads \
  -e VPN_ENABLED=yes \
  -e VPN_TYPE=wireguard \
  -e LAN_NETWORK=192.168.0.0/24 \
  -p 8080:8080 \
  --cap-add NET_ADMIN \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --restart unless-stopped \
  ghcr.io/jslay88/docker-qbittorrentvpn:latest
```

On first start, qBittorrent prints a temporary WebUI password in the container log. Username from the template is `admin`.

## Volumes

Mount both of these. The container does not keep anything else.

| Path | What is stored |
|---|---|
| `/config` | qBittorrent profile, VPN config, and the WebUI certificate when `ENABLE_SSL` is set |
| `/downloads` | Torrent data. The template save path is `/downloads` and the temp path is `/downloads/temp` |

`/config` layout:

- `/config/qBittorrent/config/qBittorrent.conf` is copied from the template on first start. Resume data and logs are under `/config/qBittorrent/data/`.
- WireGuard config is `/config/wireguard/wg0.conf`. The file has to be named `wg0.conf`.
- OpenVPN configs go in `/config/openvpn/` and must end in `.ovpn`. `VPN_USERNAME` and `VPN_PASSWORD` are written to `/config/openvpn/credentials.conf`.
- `ENABLE_SSL` writes `/config/qBittorrent/config/WebUICertificate.crt` and `WebUIKey.key` when those files are missing.

qBittorrent runs as `PUID`:`PGID` (root if unset). The mounted directories should be owned by that user and group.

If you point the save path at something other than `/downloads`, mount that path too. Otherwise the data is gone when the container is removed.

## NAT-PMP

Off unless you set it. This is for Proton (or any other provider that forwards a port with NAT-PMP on the WireGuard gateway).

```bash
-e NATPMP_ENABLED=yes \
-e VPN_TYPE=wireguard
```

The loop reads `Address` from `wg0.conf`. A Proton `/32` like `10.2.0.2/32` uses gateway `10.2.0.1`. Override with `NATPMP_GATEWAY` if that guess is wrong.

It renews the UDP and TCP mapping every 45 seconds (lifetime 60, same as Proton's docs) and sets qBittorrent's listen port when the mapped port changes. `NATPMP_LIFETIME` and `NATPMP_INTERVAL` override those. A failed request is logged and retried. It does not stop qBittorrent.

While this is on, localhost inside the container can call the WebUI API without a password so the loop can update the port. Clients outside the container still have to log in.

## Variables

| Variable | Required | What it does | Default |
|---|---|---|---|
| `VPN_ENABLED` | yes | `yes` or `no` | `yes` |
| `VPN_TYPE` | yes | `wireguard` or `openvpn` | `openvpn` |
| `LAN_NETWORK` | yes, when the VPN is on | Comma-separated CIDRs that should bypass the tunnel | |
| `VPN_USERNAME` / `VPN_PASSWORD` | no | Written into the OpenVPN credentials file | |
| `VPN_OPTIONS` | no | Extra arguments appended to the `openvpn` command | |
| `NAME_SERVERS` | no | Comma-separated resolvers | `1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4` |
| `PUID` / `PGID` | no | User and group for `/config` and `/downloads` | `root` |
| `UMASK` | no | | `002` |
| `ENABLE_SSL` | no | Generate a WebUI cert and turn HTTPS on | unset, so HTTP |
| `LEGACY_IPTABLES` | no | Use `iptables-legacy` | unset |
| `ADDITIONAL_PORTS` | no | Extra TCP ports allowed through the killswitch on the docker interface | |
| `NATPMP_ENABLED` | no | `yes` turns on NAT-PMP. Only with `VPN_TYPE=wireguard` | `no` |
| `NATPMP_GATEWAY` | no | NAT-PMP gateway. Otherwise taken from `wg0.conf` | |
| `NATPMP_LIFETIME` | no | Mapping lifetime in seconds | `60` |
| `NATPMP_INTERVAL` | no | Seconds between renewals | `45` |
| `INSTALL_PYTHON3` | no | `apk add python3` on startup, for search plugins | `no` |
| `HEALTH_CHECK_HOST` | no | Host the health check pings through the tunnel | `one.one.one.one` |
| `HEALTH_CHECK_INTERVAL` | no | Seconds between pings | `300` |
| `HEALTH_CHECK_AMOUNT` | no | Ping count per check | `1` |
| `HEALTH_CHECK_SILENT` | no | `1` hides the "network is up" line | `1` |
| `RESTART_CONTAINER` | no | Exit when the health check fails so Docker restarts it | `yes` |

`LAN_NETWORK` has to include your LAN, or the WebUI is only reachable from inside the docker bridge. The killswitch drops everything that is not the tunnel, the VPN endpoint, or those LAN routes.

## Ports

| Port | Proto | What |
|---|---|---|
| `8080` | TCP | WebUI |
| `8999` | TCP/UDP | Default listen port in the template. NAT-PMP replaces this when it is enabled. You do not publish the forwarded port. It lives on the VPN side. |
