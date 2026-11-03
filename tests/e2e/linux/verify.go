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
	"path"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	tc "github.com/testcontainers/testcontainers-go"

	"github.com/version-fox/vfox-gradle/tests/e2e/common"
)

// verifySearch proves `vfox search gradle` (the Available hook, which reads the
// release page of gradle.org) lists the releases the suite installs, newest
// first with none twice. It returns the versions in the order listed.
func verifySearch(ctx context.Context, t *testing.T, ctr tc.Container, wanted ...string) []string {
	t.Helper()
	out := execRetry(ctx, t, ctr, "vfox search gradle", "vfox search gradle")
	searched := common.SearchedVersions(out)
	require.NotEmptyf(t, searched, "vfox search gradle listed no version\n--- output ---\n%s", out)
	require.Truef(t, common.NewestFirst(searched), "vfox search gradle must list each release once, newest first\n--- output ---\n%s", out)
	for _, version := range wanted {
		require.Containsf(t, searched, version, "vfox search gradle must list %s\n--- output ---\n%s", version, out)
	}
	t.Logf("PASS vfox search gradle lists %d releases, %s first", len(searched), searched[0])
	return searched
}

// verifySearchMarks proves `vfox search gradle` marks a version as installed.
func verifySearchMarks(ctx context.Context, t *testing.T, ctr tc.Container, version string) {
	t.Helper()
	out := execOK(ctx, t, ctr, "vfox search gradle")
	require.Truef(t, common.SearchedInstalled(out, version), "vfox search gradle must mark %s as installed\n--- output ---\n%s", version, out)
	t.Logf("PASS vfox search gradle marks %s as installed", version)
}

// checkLatest proves `latest` is the first entry of the search, which is the
// newest release (see verifySearch): vfox core takes it from the Available
// hook. The install goes to a mirror that does not exist, so it prints which
// release it took and fails on the request for its checksum, and nothing is
// downloaded.
func checkLatest(ctx context.Context, t *testing.T, ctr tc.Container, newest string) {
	t.Helper()
	code, out := execRun(ctx, t, ctr, "vfox install gradle@latest", common.MirrorEnv+"="+common.BogusMirror)
	require.NotZerof(t, code, "installing through a mirror that does not exist must fail\n--- output ---\n%s", out)
	require.Equalf(t, newest, common.LatestVersion(out), "`latest` must be the first release vfox search lists\n--- output ---\n%s", out)
	require.Truef(t, common.AskedBogusMirror(out, newest), "the checksum of %s must be asked for at the mirror\n--- output ---\n%s", newest, out)
	t.Logf("PASS gradle@latest is %s, the first release vfox search lists", newest)
}

// checkMissingRejected proves a name no release has (see common.MissingVersions)
// fails instead of installing something else: the checksum request answers 404,
// the plugin goes on without a checksum, and the download ends in 404, which
// vfox reports as "source file not found". Nothing is installed.
func checkMissingRejected(ctx context.Context, t *testing.T, ctr tc.Container) {
	t.Helper()
	for _, version := range common.MissingVersions {
		spec := "gradle@" + version
		common.Retry(ctx, t, "vfox install "+spec+" (must fail)", func() (int, string) {
			code, out := execRun(ctx, t, ctr, "vfox install "+spec)
			if code == 0 {
				t.Fatalf("installing the unpublished %s unexpectedly succeeded\n--- output ---\n%s", spec, out)
			}
			// Any other failure (e.g. gradle.org unreachable) is retried like
			// the other network-touching calls.
			if strings.Contains(out, "source file not found") {
				return 0, out
			}
			return code, out
		})
		// The exit code does not matter: `vfox list` of a plugin with nothing
		// installed exits non-zero.
		_, out := execRun(ctx, t, ctr, "vfox list gradle")
		require.NotContainsf(t, common.ListedVersions(out), version, "%s must not be installed", spec)
		t.Logf("PASS %s is rejected", spec)
	}
}

// checkBogusMirror proves the plugin honours $VFOX_GRADLE_MIRRORS: installing
// through a mirror that does not exist (see common.BogusMirror) must fail on the
// request for the checksum, and vfox's error must name the URL it asked for, the
// mirror and the file name with one slash between, though the value ends in a
// slash. Before the plugin read the variable, it downloaded from
// services.gradle.org and the install succeeded.
func checkBogusMirror(ctx context.Context, t *testing.T, ctr tc.Container, version string) {
	t.Helper()
	label := "vfox install gradle@" + version + " through a mirror that does not exist"
	common.Retry(ctx, t, label+" (must fail)", func() (int, string) {
		code, out := execRun(ctx, t, ctr, "vfox install gradle@"+version, common.MirrorEnv+"="+common.BogusMirror+"/")
		if code == 0 {
			t.Fatalf("%s unexpectedly succeeded\n--- output ---\n%s", label, out)
		}
		if common.AskedBogusMirror(out, version) {
			return 0, out
		}
		return code, out
	})
	t.Logf("PASS the download of gradle@%s goes to the mirror that %s names", version, common.MirrorEnv)
}

// checkChecksumStatus proves a mirror that answers the request for the checksum
// with something else than 200 or 404 stops the install with a message that
// names the status and the address, and that nothing is downloaded. The plugin
// used to return nothing, and vfox printed only "no installable runtime
// provided".
func checkChecksumStatus(ctx context.Context, t *testing.T, ctr tc.Container, m mirror, version string, status string) {
	t.Helper()
	code, out := execRun(ctx, t, ctr, "vfox install gradle@"+version, common.MirrorEnv+"="+m.url()+"/")
	require.NotZerof(t, code, "installing through a mirror that answers %s must fail\n--- output ---\n%s", status, out)
	want := "checksum request failed: HTTP " + status + " from " + m.url() + "/gradle-" + version + "-bin.zip.sha256"
	require.Containsf(t, common.StripANSI(out), want, "the error must name the status and the address\n--- output ---\n%s", out)
	t.Logf("PASS a mirror that answers %s for the checksum stops the install with %q", status, want)
}

// verifyPublishedDigest proves the digest vfox verified the download against is
// the one Gradle publishes for the release, not just some digest: Gradle's
// .sha256 file holds the digest alone.
func verifyPublishedDigest(ctx context.Context, t *testing.T, ctr tc.Container, version, verified string) {
	t.Helper()
	url := "https://services.gradle.org/distributions/gradle-" + version + "-bin.zip.sha256"
	published := strings.ToLower(strings.TrimSpace(execRetry(ctx, t, ctr, "fetch "+url,
		"curl --fail --silent --show-error --location "+shQuote(url))))
	require.Equalf(t, published, verified, "vfox must verify gradle@%s against the digest Gradle publishes", version)
	t.Logf("PASS the digest of gradle@%s is the one Gradle publishes", version)
}

// buildScript is a Gradle build with one task, run to see that the unpacked
// distribution works as a whole: the launcher, the libraries under lib/ and
// the Groovy that compiles the script.
const buildScript = `
cat > build.gradle <<'GRADLE'
tasks.register('hello') {
    doLast {
        println "hello from Gradle ${gradle.gradleVersion}"
    }
}
GRADLE
`

// verifyToolchain proves that, once version is selected with `vfox use
// --global`, a new activated shell has the Gradle of that release: `gradle
// --version` reports it, GRADLE_HOME is its directory (a symlink vfox keeps
// pointed at the release in use), `gradle` is bin/gradle in that directory,
// and a build runs. The JDK Gradle runs on is the image's.
func verifyToolchain(ctx context.Context, t *testing.T, ctr tc.Container, version string) {
	t.Helper()
	out := execOK(ctx, t, ctr, activated(`set -e
gradle --version
echo "GRADLE_HOME=$GRADLE_HOME"
echo "GRADLE_HOME_REAL=$(readlink -f "$GRADLE_HOME")"
echo "GRADLE_BIN_REAL=$(readlink -f "$(command -v gradle)")"
echo "CURRENT=$(vfox current gradle)"
dir=$(mktemp --directory)
cd "$dir"
printf "rootProject.name = 'e2e'\n" > settings.gradle`+buildScript+`
gradle --quiet --no-daemon hello`))
	out = common.StripANSI(out)

	require.Equalf(t, version, common.GradleVersion(out), "gradle --version must report %s\n--- output ---\n%s", version, out)
	home := field(out, "GRADLE_HOME_REAL")
	require.Equalf(t, "gradle-"+version, path.Base(home), "GRADLE_HOME must be the directory of gradle@%s\n--- output ---\n%s", version, out)
	require.Equalf(t, home+"/bin/gradle", field(out, "GRADLE_BIN_REAL"), "gradle on the PATH must be bin/gradle of GRADLE_HOME\n--- output ---\n%s", out)
	require.Containsf(t, field(out, "CURRENT"), version, "vfox current gradle must report %s\n--- output ---\n%s", version, out)
	require.Containsf(t, out, "hello from Gradle "+version, "a build must run with gradle@%s\n--- output ---\n%s", version, out)
	t.Logf("PASS gradle@%s is in use: GRADLE_HOME %s (%s), and a build runs", version, field(out, "GRADLE_HOME"), home)
}

// field returns the value of a "KEY=value" line of out, or "" when there is none.
func field(out, key string) string {
	for _, line := range strings.Split(out, "\n") {
		if value, ok := strings.CutPrefix(strings.TrimRight(line, "\r"), key+"="); ok {
			return value
		}
	}
	return ""
}

// verifySwitch proves the release in use follows `vfox use`: selecting the
// second release and then the first again changes GRADLE_HOME, `gradle` and the
// version it reports each time (see verifyToolchain), `vfox list gradle` shows
// both, and uninstalling the one not in use leaves the other working.
func verifySwitch(ctx context.Context, t *testing.T, ctr tc.Container, first, second string) {
	t.Helper()
	listed := common.ListedVersions(execOK(ctx, t, ctr, "vfox list gradle"))
	require.ElementsMatchf(t, []string{first, second}, listed, "vfox list gradle must show both releases")

	useGradle(ctx, t, ctr, second)
	verifyToolchain(ctx, t, ctr, second)
	useGradle(ctx, t, ctr, first)
	verifyToolchain(ctx, t, ctr, first)

	out := execOK(ctx, t, ctr, "vfox uninstall gradle@"+second)
	require.Containsf(t, common.StripANSI(out), "Uninstalled gradle@"+second+" successfully!", "vfox uninstall gradle@%s", second)
	listed = common.ListedVersions(execOK(ctx, t, ctr, "vfox list gradle"))
	require.Equalf(t, []string{first}, listed, "only gradle@%s must be left", first)
	verifyToolchain(ctx, t, ctr, first)
	t.Logf("PASS vfox use switches between gradle@%s and gradle@%s, and vfox uninstall removes one", first, second)
}
