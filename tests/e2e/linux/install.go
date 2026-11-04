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
	"testing"

	tc "github.com/testcontainers/testcontainers-go"

	"github.com/version-fox/vfox-gradle/tests/e2e/common"
)

// installGradle installs one release and returns the digest vfox verified the
// download against (see common.CheckVerified). extraEnv entries ("K=V") are set
// for the install only, as VFOX_GRADLE_MIRRORS is for an install through a mirror.
func installGradle(ctx context.Context, t *testing.T, ctr tc.Container, version string, extraEnv ...string) string {
	t.Helper()
	label := "vfox install gradle@" + version
	out := execRetry(ctx, t, ctr, label, "vfox install gradle@"+version, extraEnv...)
	common.CheckInstalled(t, out, version)
	digest := common.CheckVerified(t, out, version)
	t.Logf("PASS gradle@%s installed, verified against %s", version, digest)
	return digest
}

// useGradle selects the installed release globally; `vfox use` needs the
// activate context (see exec.go).
func useGradle(ctx context.Context, t *testing.T, ctr tc.Container, version string) {
	t.Helper()
	execOK(ctx, t, ctr, activated("vfox use --global gradle@"+version))
}
