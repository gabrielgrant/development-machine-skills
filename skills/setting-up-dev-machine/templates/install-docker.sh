#!/usr/bin/env bash
# Host script: Docker Engine from Docker's apt repo. Idempotent.
# Drop into $SERVER_CONFIG_DIR/host/scripts.d/ — apply.sh runs it before
# manifest convergence. Also add the docker packages (docker-ce,
# docker-ce-cli, containerd.io, docker-buildx-plugin,
# docker-compose-plugin) to host/apt-packages.txt so the manifest stays
# the complete declarative record and drift checks stay clean.
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
    exit 0
fi

echo "==> Installing Docker Engine"
arch=$(dpkg --print-architecture)
codename=$(. /etc/os-release && echo "$VERSION_CODENAME")

sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

list=/etc/apt/sources.list.d/docker.list
if [ ! -f "$list" ]; then
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $codename stable" |
        sudo tee "$list" > /dev/null
fi

sudo apt-get update -q
sudo apt-get install -qy docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
echo "==> Docker installed; log out/in for group membership to apply"
