# qBittorrent, OpenVPN and WireGuard
# Modified fork of https://github.com/DyonR/docker-qbittorrentvpn
# Base image is Alpine. qBittorrent and libtorrent are built from source.

ARG ALPINE_IMAGE=alpine:3

FROM ${ALPINE_IMAGE} AS build

ARG QBITTORRENT_TAG=release-5.2.3
ARG LIBTORRENT_TAG=v2.0.15

RUN apk add --no-cache \
		build-base \
		ca-certificates \
		cmake \
		curl \
		linux-headers \
		boost-dev \
		openssl-dev \
		pkgconf \
		qt6-qtbase-dev \
		qt6-qtbase-private-dev \
		qt6-qttools-dev \
		samurai \
		tar \
		xz \
		zlib-dev

WORKDIR /src

RUN set -eux; \
	libtorrent_version="${LIBTORRENT_TAG#v}"; \
	curl -fsSL -o libtorrent.tar.gz \
		"https://github.com/arvidn/libtorrent/releases/download/${LIBTORRENT_TAG}/libtorrent-rasterbar-${libtorrent_version}.tar.gz"; \
	tar -xzf libtorrent.tar.gz; \
	cmake -S "libtorrent-rasterbar-${libtorrent_version}" -B /tmp/lt-build -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_CXX_STANDARD=17 \
		-Dbuild_tests=OFF \
		-Dpython-bindings=OFF \
		-Dwebtorrent=OFF; \
	cmake --build /tmp/lt-build --parallel "$(nproc)"; \
	cmake --install /tmp/lt-build; \
	rm -rf /tmp/lt-build libtorrent.tar.gz "libtorrent-rasterbar-${libtorrent_version}"

RUN set -eux; \
	curl -fsSL -o qbittorrent.tar.gz \
		"https://github.com/qbittorrent/qBittorrent/archive/refs/tags/${QBITTORRENT_TAG}.tar.gz"; \
	tar -xzf qbittorrent.tar.gz; \
	cmake -S "qBittorrent-${QBITTORRENT_TAG}" -B /tmp/qbt-build -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DGUI=OFF \
		-DWEBUI=ON \
		-DSTACKTRACE=OFF \
		-DTESTING=OFF; \
	cmake --build /tmp/qbt-build --parallel "$(nproc)"; \
	cmake --install /tmp/qbt-build; \
	if [ ! -x /usr/bin/qbittorrent-nox ]; then \
		install -m755 /tmp/qbt-build/qbittorrent-nox /usr/bin/qbittorrent-nox; \
	fi; \
	rm -rf /tmp/qbt-build qbittorrent.tar.gz "qBittorrent-${QBITTORRENT_TAG}"

FROM ${ALPINE_IMAGE}

ARG QBITTORRENT_VERSION=5.2.3
ARG LIBTORRENT_TAG=v2.0.15
ARG ALPINE_DIGEST=

RUN apk add --no-cache \
		bash \
		boost \
		ca-certificates \
		curl \
		dos2unix \
		findutils \
		grep \
		iproute2 \
		iptables \
		iptables-legacy \
		libnatpmp \
		moreutils \
		net-tools \
		openresolv \
		openssl \
		openvpn \
		procps \
		qt6-qtbase \
		qt6-qtbase-sqlite \
		shadow \
		su-exec \
		wireguard-tools \
	&& mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent \
	&& sed -i '/net\.ipv4\.conf\.all\.src_valid_mark/d' "$(command -v wg-quick)"

COPY --from=build /usr/bin/qbittorrent-nox /usr/bin/qbittorrent-nox
COPY --from=build /usr/lib/libtorrent-rasterbar.so* /usr/lib/

COPY openvpn/ /etc/openvpn/
COPY qbittorrent/ /etc/qbittorrent/

RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/openvpn/*.sh

LABEL org.opencontainers.image.source="https://github.com/jslay88/docker-qbittorrentvpn" \
	org.opencontainers.image.description="qBittorrent-nox with WireGuard or OpenVPN and an iptables killswitch" \
	org.opencontainers.image.licenses="GPL-3.0-only" \
	org.opencontainers.image.version="${QBITTORRENT_VERSION}" \
	org.opencontainers.image.base.name="alpine:3" \
	org.opencontainers.image.base.digest="${ALPINE_DIGEST}" \
	io.github.jslay88.libtorrent-version="${LIBTORRENT_TAG}"

VOLUME /config /downloads

EXPOSE 8080
EXPOSE 8999
EXPOSE 8999/udp

CMD ["/bin/bash", "/etc/openvpn/start.sh"]
