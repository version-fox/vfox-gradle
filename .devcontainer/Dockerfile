# Copyright 2026 Han Li and contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The repository dev container (see docs/e2e.md): a Linux userland that is
# identical on every host platform — Linux amd64/arm64 natively, Windows
# amd64/arm64 through Docker Desktop's Linux-container mode. It carries the
# pinned Go toolchain the E2E suite and the local checks need, matching the
# setup-go version CI uses, plus the Lua, workflow and license tooling pinned in
# the lint and license workflows, and the vfox release that runs the hook tests
# (vfox plugin test) in the test workflow.
#
# The suite itself runs testcontainers against the host daemon through the
# socket mounted by devcontainer.json (Docker-out-of-Docker), so the target
# containers are spawned exactly as a native CI runner spawns them.
#
# The image is multi-arch (linux/amd64 and linux/arm64); the Lua and vfox
# downloads below select their asset per target arch.

FROM golang:1.27.1

# Docker CLI (client only): drives the host daemon from the shell, the same
# daemon the suite drives through the Docker Go API.
COPY --from=docker:29-cli /usr/local/bin/docker /usr/local/bin/docker

# Keep the tool versions below in step with .github/workflows/lint.yml
# (stylua-action's version, the `mise x aqua:...` line and the actionlint
# image) and test.yml (vfox).
ARG STYLUA_VERSION=2.5.2
ARG LUA_LANGUAGE_SERVER_VERSION=3.19.1
ARG VFOX_VERSION=1.0.13
ARG ACTIONLINT_VERSION=1.7.12

# Heredocs need BuildKit, which the dev container tooling uses by default. The
# E2E target Dockerfile stays on the chained-`;` form: testcontainers-go's
# build path cannot use BuildKit (see tests/e2e/linux/Dockerfile).

RUN <<EOF
set -o errexit -o nounset -o xtrace
apt-get update
apt-get install --assume-yes --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    zip
rm --recursive --force /var/lib/apt/lists/*
case "$(dpkg --print-architecture)" in
    amd64) stylua_asset=stylua-linux-x86_64.zip; luals_asset="lua-language-server-${LUA_LANGUAGE_SERVER_VERSION}-linux-x64.tar.gz"; vfox_dir="vfox_${VFOX_VERSION}_linux_x86_64" ;;
    arm64) stylua_asset=stylua-linux-aarch64.zip; luals_asset="lua-language-server-${LUA_LANGUAGE_SERVER_VERSION}-linux-arm64.tar.gz"; vfox_dir="vfox_${VFOX_VERSION}_linux_aarch64" ;;
    *) echo "FAIL unsupported architecture $(dpkg --print-architecture)" >&2; exit 1 ;;
esac
curl --fail --silent --show-error --location --output /tmp/stylua.zip \
    "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/${stylua_asset}"
unzip -q /tmp/stylua.zip -d /usr/local/bin
rm --force /tmp/stylua.zip
curl --fail --silent --show-error --location --output /tmp/luals.tar.gz \
    "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LANGUAGE_SERVER_VERSION}/${luals_asset}"
mkdir --parents /opt/lua-language-server
tar --extract --gzip --file /tmp/luals.tar.gz --directory /opt/lua-language-server
rm --force /tmp/luals.tar.gz
ln --symbolic /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server
curl --fail --silent --show-error --location --output /tmp/vfox.tar.gz \
    "https://github.com/version-fox/vfox/releases/download/v${VFOX_VERSION}/${vfox_dir}.tar.gz"
tar --extract --gzip --file /tmp/vfox.tar.gz --directory /usr/local/bin --strip-components=1 "${vfox_dir}/vfox"
rm --force /tmp/vfox.tar.gz
stylua --version
lua-language-server --version
vfox --version
EOF

# Workflow lint at the version the lint workflow runs (actionlint), and
# license-header tooling at the version pinned by .github/workflows/license.yml
# (SkyWalking Eyes v0.9.0).
RUN <<EOF
set -o errexit -o nounset -o xtrace
GOBIN=/usr/local/bin go install "github.com/rhysd/actionlint/cmd/actionlint@v${ACTIONLINT_VERSION}"
GOBIN=/usr/local/bin go install github.com/apache/skywalking-eyes/cmd/license-eye@v0.9.0
command -v actionlint license-eye
EOF
