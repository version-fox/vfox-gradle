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

package windows

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	tc "github.com/testcontainers/testcontainers-go"

	"github.com/version-fox/vfox-gradle/tests/e2e/common"
)

// installGradle installs one release from services.gradle.org and returns the
// digest vfox verified the download against (see common.CheckVerified). Install
// runs plain: vfox.exe resolves through the slot PATH override.
func installGradle(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, version string) string {
	t.Helper()
	spec := "gradle@" + version
	out := execRetry(ctx, t, ctr, "vfox install "+spec, "vfox install "+pwshQuote(spec), box.vars...)
	common.CheckInstalled(t, out, version)
	digest := common.CheckVerified(t, out, version)
	t.Logf("PASS %s installed, verified against %s", spec, digest)
	return digest
}

// useGradle selects the installed release globally; `vfox use` needs the
// activation context captured by fetchActivation. On Windows a global `use`
// also writes the variables to the registry of the account, here the
// container's, so the suite never runs `vfox use --global` on a machine of its
// own.
func useGradle(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, activation, version string) {
	t.Helper()
	out := execOK(ctx, t, ctr, activated(activation, "vfox use --global "+pwshQuote("gradle@"+version)), box.vars...)
	require.Containsf(t, common.StripANSI(out), "Now using gradle@"+version+".",
		"vfox use --global gradle@%s must select it\n--- output ---\n%s", version, out)
}
