// Copyright 2026 Han Li and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package linux

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	tc "github.com/testcontainers/testcontainers-go"

	"github.com/version-fox/vfox-gradle/tests/e2e/common"
)

// setupVfox installs vfox (release, or builds main with the in-image Go
// toolchain) and registers the local gradle plugin.
func setupVfox(ctx context.Context, t *testing.T, ctr tc.Container, vfoxVersion string) {
	t.Helper()
	work := strings.TrimSpace(execOK(ctx, t, ctr, "mktemp --directory"))
	// The container is removed after the test, but clean up anyway so
	// repeated local runs don't leak /tmp.
	defer func() {
		_, _ = execRun(ctx, t, ctr, fmt.Sprintf("rm --recursive --force %q", work))
	}()

	if vfoxVersion == "main" {
		execOK(ctx, t, ctr, fmt.Sprintf(
			"git clone --depth 1 https://github.com/version-fox/vfox %q/src && (cd %q/src && CGO_ENABLED=0 go build -trimpath -o /usr/local/bin/vfox .)",
			work, work))
	} else {
		// A pipeline exits with the status of its last command, so without
		// pipefail a download that fails leaves bash an empty script and
		// the install passes without vfox, which the next step then misses.
		execRetry(ctx, t, ctr, "install vfox",
			"set -o pipefail; curl --fail --silent --show-error --location https://raw.githubusercontent.com/version-fox/vfox/main/install.sh | bash")
	}
	execOK(ctx, t, ctr, fmt.Sprintf(
		"(cd /e2e && zip -qr %q/gradle.zip metadata.lua hooks lib) && vfox add gradle --source %q/gradle.zip",
		work, work))
	t.Logf("PASS %s with the local gradle plugin", strings.TrimSpace(execOK(ctx, t, ctr, "vfox --version")))
}

// checkNotes proves the notes printed by `vfox info gradle` point to the
// README (see common.ReadmeURL), which says how to use a mirror and that
// Gradle needs a JDK.
func checkNotes(ctx context.Context, t *testing.T, ctr tc.Container) {
	t.Helper()
	out := execOK(ctx, t, ctr, "vfox info gradle")
	require.Containsf(t, common.StripANSI(out), common.ReadmeURL,
		"the notes of vfox info gradle must point to the README\n--- output ---\n%s", out)
	t.Logf("PASS the notes of vfox info gradle point to %s", common.ReadmeURL)
}
