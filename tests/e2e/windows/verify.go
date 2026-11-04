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
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	tc "github.com/testcontainers/testcontainers-go"

	"github.com/version-fox/vfox-gradle/tests/e2e/common"
)

// NOTE: the markers asserted here are part of the plugin's or vfox's
// user-facing contract (see hooks/ lib/). If either side rewords them,
// update this file and tests/e2e/linux/verify.go together.

// verifySearch proves `vfox search gradle` (the Available hook, which reads the
// release page of gradle.org) lists the releases the suite installs, newest
// first with none twice. It returns the versions in the order listed.
func verifySearch(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, wanted ...string) []string {
	t.Helper()
	out := execRetry(ctx, t, ctr, "vfox search gradle", "vfox search gradle", box.vars...)
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
func verifySearchMarks(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, version string) {
	t.Helper()
	out := execOK(ctx, t, ctr, "vfox search gradle", box.vars...)
	require.Truef(t, common.SearchedInstalled(out, version), "vfox search gradle must mark %s as installed\n--- output ---\n%s", version, out)
	t.Logf("PASS vfox search gradle marks %s as installed", version)
}

// bogusMirrorEnv is the environment of a command that installs through a mirror
// that does not exist (see common.BogusMirror), on top of the slot's.
func bogusMirrorEnv(box slotBox, slash string) []string {
	return append(slices.Clone(box.vars), common.MirrorEnv+"="+common.BogusMirror+slash)
}

// checkLatest proves `latest` is the first entry of the search, which is the
// newest release (see verifySearch): vfox core takes it from the Available
// hook. The install goes to a mirror that does not exist, so it prints which
// release it took and fails on the request for its checksum, and nothing is
// downloaded.
func checkLatest(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, newest string) {
	t.Helper()
	code, out := execRun(ctx, t, ctr, "vfox install gradle@latest", bogusMirrorEnv(box, "")...)
	require.NotZerof(t, code, "installing through a mirror that does not exist must fail\n--- output ---\n%s", out)
	require.Equalf(t, newest, common.LatestVersion(out), "`latest` must be the first release vfox search lists\n--- output ---\n%s", out)
	require.Truef(t, common.AskedBogusMirror(out, newest), "the checksum of %s must be asked for at the mirror\n--- output ---\n%s", newest, out)
	t.Logf("PASS gradle@latest is %s, the first release vfox search lists", newest)
}

// checkMissingRejected proves a name no release has (see common.MissingVersions)
// fails instead of installing something else: the checksum request answers 404,
// the plugin goes on without a checksum, and the download ends in 404, which
// vfox reports as "source file not found". Nothing is installed.
func checkMissingRejected(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox) {
	t.Helper()
	for _, version := range common.MissingVersions {
		spec := "gradle@" + version
		common.Retry(ctx, t, "vfox install "+spec+" (must fail)", func() (int, string) {
			code, out := execRun(ctx, t, ctr, "vfox install "+pwshQuote(spec), box.vars...)
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
		_, out := execRun(ctx, t, ctr, "vfox list gradle", box.vars...)
		require.NotContainsf(t, common.ListedVersions(out), version, "%s must not be installed", spec)
		t.Logf("PASS %s is rejected", spec)
	}
}

// checkBogusMirror proves the plugin honours $VFOX_GRADLE_MIRRORS in a pwsh
// exec: installing through a mirror that does not exist (see
// common.BogusMirror) must fail on the request for the checksum, and vfox's
// error must name the URL it asked for, the mirror and the file name with one
// slash between, though the value ends in a slash.
func checkBogusMirror(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, version string) {
	t.Helper()
	label := "vfox install gradle@" + version + " through a mirror that does not exist"
	common.Retry(ctx, t, label+" (must fail)", func() (int, string) {
		code, out := execRun(ctx, t, ctr, "vfox install "+pwshQuote("gradle@"+version), bogusMirrorEnv(box, "/")...)
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

// verifyPublishedDigest proves the digest vfox verified the download against is
// the one Gradle publishes for the release, not just some digest: Gradle's
// .sha256 file holds the digest alone. curl.exe is Windows' own; `curl` in
// PowerShell can be an alias of Invoke-WebRequest.
func verifyPublishedDigest(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, version, verified string) {
	t.Helper()
	url := "https://services.gradle.org/distributions/gradle-" + version + "-bin.zip.sha256"
	published := strings.ToLower(strings.TrimSpace(execRetry(ctx, t, ctr, "fetch "+url,
		"curl.exe --fail --silent --show-error --location "+pwshQuote(url), box.vars...)))
	require.Equalf(t, published, verified, "vfox must verify gradle@%s against the digest Gradle publishes", version)
	t.Logf("PASS the digest of gradle@%s is the one Gradle publishes", version)
}

// buildScript is a Gradle build with one task, run to see that the unpacked
// distribution works as a whole: the launcher, the libraries under lib/ and
// the Groovy that compiles the script.
const buildScript = `tasks.register('hello') {
    doLast {
        println "hello from Gradle ${gradle.gradleVersion}"
    }
}
`

// toolchainScript is the pwsh that prints the facts verifyToolchain checks, as
// KEY=value lines (see common.Field) between the output of gradle itself, and
// runs a build in dir. It runs after the export of `vfox env`, with the version
// in use.
//
// vfox keeps the release in use behind a link, which is a junction on Windows,
// and sets GRADLE_HOME to it. Target is the directory the junction points to,
// and what Get-Item shows for a directory that is no link is nothing.
// Get-Command finds gradle.bat by PATHEXT, where the extensionless script of
// bin/gradle is no command on Windows. Both paths go through GetFullPath,
// because the hook adds "/bin" to the path of the link, and the PATH entry
// then has a slash among the backslashes.
func toolchainScript(dir string) string {
	return strings.Join([]string{
		`gradle --version`,
		`'GRADLE_HOME=' + $env:GRADLE_HOME`,
		`$gradleHome = Get-Item -LiteralPath $env:GRADLE_HOME`,
		`$linkTarget = $gradleHome.Target | Select-Object -First 1`,
		`'GRADLE_HOME_REAL=' + $(if ($linkTarget) { $linkTarget } else { $gradleHome.FullName })`,
		`$launcher = Get-Command gradle -CommandType Application | Select-Object -First 1`,
		`'GRADLE_BIN=' + [IO.Path]::GetFullPath($launcher.Source)`,
		`'GRADLE_BIN_WANT=' + [IO.Path]::GetFullPath((Join-Path $env:GRADLE_HOME 'bin\gradle.bat'))`,
		`'CURRENT=' + (vfox current gradle)`,
		fmt.Sprintf(`New-Item -ItemType Directory -Force -Path %s | Out-Null`, pwshQuote(dir)),
		fmt.Sprintf(`Set-Content -Path %s -Value %s`, pwshQuote(dir+`\settings.gradle`), pwshQuote("rootProject.name = 'e2e'")),
		fmt.Sprintf(`Set-Content -Path %s -Value %s`, pwshQuote(dir+`\build.gradle`), pwshQuote(buildScript)),
		fmt.Sprintf(`Set-Location -LiteralPath %s`, pwshQuote(dir)),
		`gradle --quiet --no-daemon hello`,
	}, "\n")
}

// windowsPath renders a Windows path the way two spellings of it compare equal:
// backslashes only, and in lower case, as the file system takes them.
func windowsPath(p string) string {
	return strings.ToLower(strings.ReplaceAll(p, "/", `\`))
}

// verifyToolchain proves that, once version is selected with `vfox use
// --global`, a new activated shell has the Gradle of that release: `gradle
// --version` reports it, GRADLE_HOME is the link vfox keeps pointed at the
// release in use and resolves to its directory in the cache of the vfox home,
// `gradle` is bin\gradle.bat in that link, and a build runs. The JDK Gradle
// runs on is the image's.
func verifyToolchain(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, activation, version string) {
	t.Helper()
	out := execOK(ctx, t, ctr, activatedEnv(activation, toolchainScript(box.tmp+`\e2e-gradle`)), box.vars...)
	out = common.StripANSI(out)

	require.Equalf(t, version, common.GradleVersion(out), "gradle --version must report %s\n--- output ---\n%s", version, out)
	home := common.Field(out, "GRADLE_HOME_REAL")
	wantHome := `\cache\gradle\v-` + version + `\gradle-` + version
	require.Truef(t, strings.HasSuffix(windowsPath(home), windowsPath(wantHome)),
		"GRADLE_HOME must resolve to the directory of gradle@%s, ...%s, not %q\n--- output ---\n%s", version, wantHome, home, out)
	bin := common.Field(out, "GRADLE_BIN")
	require.Equalf(t, windowsPath(common.Field(out, "GRADLE_BIN_WANT")), windowsPath(bin),
		"gradle on the PATH must be bin\\gradle.bat of GRADLE_HOME\n--- output ---\n%s", out)
	require.Truef(t, strings.HasSuffix(windowsPath(bin), `\bin\gradle.bat`),
		"gradle on the PATH must be the batch file, not %q\n--- output ---\n%s", bin, out)
	require.Containsf(t, common.Field(out, "CURRENT"), version, "vfox current gradle must report %s\n--- output ---\n%s", version, out)
	require.Containsf(t, out, "hello from Gradle "+version, "a build must run with gradle@%s\n--- output ---\n%s", version, out)
	t.Logf("PASS gradle@%s is in use: GRADLE_HOME %s (%s), launched by %s, and a build runs",
		version, common.Field(out, "GRADLE_HOME"), home, bin)
}

// verifySwitch proves the release in use follows `vfox use`: selecting the
// second release and then the first again changes GRADLE_HOME, `gradle` and the
// version it reports each time (see verifyToolchain), `vfox list gradle` shows
// both, and uninstalling the one not in use leaves the other working. Windows
// refuses to delete a file that a process has open, so an uninstall that fails
// here points at a Gradle that is still running.
func verifySwitch(ctx context.Context, t *testing.T, ctr tc.Container, box slotBox, activation, first, second string) {
	t.Helper()
	listed := common.ListedVersions(execOK(ctx, t, ctr, "vfox list gradle", box.vars...))
	require.ElementsMatchf(t, []string{first, second}, listed, "vfox list gradle must show both releases")

	useGradle(ctx, t, ctr, box, activation, second)
	verifyToolchain(ctx, t, ctr, box, activation, second)
	useGradle(ctx, t, ctr, box, activation, first)
	verifyToolchain(ctx, t, ctr, box, activation, first)

	out := execOK(ctx, t, ctr, "vfox uninstall "+pwshQuote("gradle@"+second), box.vars...)
	require.Containsf(t, common.StripANSI(out), "Uninstalled gradle@"+second+" successfully!", "vfox uninstall gradle@%s", second)
	listed = common.ListedVersions(execOK(ctx, t, ctr, "vfox list gradle", box.vars...))
	require.Equalf(t, []string{first}, listed, "only gradle@%s must be left", first)
	verifyToolchain(ctx, t, ctr, box, activation, first)
	t.Logf("PASS vfox use switches between gradle@%s and gradle@%s, and vfox uninstall removes one", first, second)
}
