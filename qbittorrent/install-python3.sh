#!/bin/bash
if ! command -v python3 >/dev/null 2>&1; then
	echo "[INFO] Python3 not yet installed, installing..." | ts '%Y-%m-%d %H:%M:%.S'
	apk add --no-cache python3
else
	echo "[INFO] Python3 is already installed, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
fi
