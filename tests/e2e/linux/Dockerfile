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

FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# NOTE: no heredoc here. This image is built through testcontainers-go, whose
# classic-builder path accepts `RUN <<EOF` but silently drops the body, and
# whose BuildKit opt-in (the API's `version=2`) fails because it closes the
# build context before the daemon has consumed it. The chained-`;` form below
# is safe on both builders.
#
# Gradle is a JVM program, so a JDK has to be on the PATH before vfox installs
# anything: openjdk-21-jdk-headless, the Java both releases the suite installs
# run on (Gradle 8.5 and later, and 9.x, support 21). golang builds vfox@main
# and the mirror stand-in; zip packs the plugin under test.
RUN set -o errexit -o nounset -o xtrace; \
    apt-get update; \
    apt-get install --assume-yes \
        ca-certificates \
        curl \
        git \
        golang \
        openjdk-21-jdk-headless \
        zip

COPY metadata.lua /e2e/metadata.lua
COPY hooks /e2e/hooks
COPY lib /e2e/lib

# The stand-in for a Gradle mirror (see tests/e2e/linux/mirror), standard
# library only, so it builds without a module.
COPY tests/e2e/linux/mirror/main.go /e2e/mirror/main.go
RUN set -o errexit -o nounset -o xtrace; \
    cd /e2e/mirror; \
    CGO_ENABLED=0 go build -trimpath -o /usr/local/bin/gradle-mirror main.go

# Long-lived container: the Go test (e2e_test.go) drives every phase through
# exec calls, so the main process just idles here.
CMD ["sleep", "infinity"]
