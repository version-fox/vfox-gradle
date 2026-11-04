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

// Package common holds the target-independent logic of the container E2E suite:
// the matrix, the pinned Gradle releases, the knobs read from the environment,
// and the parsing of what vfox, Gradle and the mirror stand-in print.
//
// The code that drives a container stays in the linux package; what can be
// checked without one lives here, where `go test -short ./...` covers it.
package common

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"regexp"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// DefaultVersion is the Gradle release every combo installs from
// services.gradle.org and uses. It is a 9.x release, written with its trailing
// .0 as Gradle names the first release of a line, and the line that needs
// Java 17 or later. Old releases stay downloadable, so the pin does not age.
const DefaultVersion = "9.0.0"

// MirrorVersion is the release every combo installs through the stand-in for a
// mirror, and switches to and from DefaultVersion. It is an 8.x release written
// without a trailing .0 (8.7, not 8.7.0), which is the other way Gradle names
// releases, and one that runs on the Java 21 of the image.
const MirrorVersion = "8.7"

// NoSumVersion is the release every combo installs last, through the stand-in
// for a mirror that keeps the zips and no .sha256 files, which is what Tencent
// Cloud's mirror has for the releases after 8.0.1. vfox has to verify the
// download against the digest Gradle publishes, and print no warning. That is
// about the digest and not about the release, so the release is a small one,
// 1.12 at 42 MB where the other two are 134 MB, and it is installed and never
// run.
const NoSumVersion = "1.12"

// MissingVersions are names no release has, which `vfox install` must reject:
// a release that does not exist (99.0), and two that exist without the .0 the
// name is given here (8.7 and 8.14 are the releases, 8.7.0 and 8.14.0 are not).
// The plugin passes the version on as typed, and the download ends in 404.
var MissingVersions = []string{"99.0", "8.7.0", "8.14.0"}

// ReadmeURL is the README the plugin's notes point to, for the mirror and the
// Java a Gradle needs.
const ReadmeURL = "https://github.com/version-fox/vfox-gradle/blob/main/README.md"

// MirrorEnv is the variable that makes the plugin download from a mirror.
const MirrorEnv = "VFOX_GRADLE_MIRRORS"

// BogusMirror is a mirror that does not exist: the name cannot resolve, so the
// request for the checksum fails, and the error names the URL it asked for.
const BogusMirror = "https://invalid.example.invalid"

// PassThroughEnvs are host env knobs recorded in each target container's
// environment, so `docker inspect` shows what a combo ran with. Forwarded only
// when set, so unset stays default.
var PassThroughEnvs = []string{
	"GRADLE_VERSION",
	"E2E_RETRY_ATTEMPTS",
}

// Combo is one matrix cell: a vfox channel.
type Combo struct {
	Vfox string
}

// Prefix renders the log prefix: "vfox <vfox>, <platform>".
func (c Combo) Prefix(platform string) string {
	return fmt.Sprintf("vfox %s, %s", c.Vfox, platform)
}

// Slug renders a docker-safe container name fragment for the combo.
func (c Combo) Slug() string {
	return Sanitize(c.Vfox)
}

// Sanitize replaces every non-ASCII-alphanumeric byte with '_' so arbitrary
// names stay valid in container names.
func Sanitize(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' {
			b.WriteByte(ch)
		} else {
			b.WriteByte('_')
		}
	}
	return b.String()
}

// NormalizeArch maps uname-style names and common aliases to docker arch names.
func NormalizeArch(s string) (string, error) {
	switch strings.ToLower(s) {
	case "x86_64", "x64", "amd64":
		return "amd64", nil
	case "aarch64", "arm64":
		return "arm64", nil
	default:
		return "", fmt.Errorf("unknown architecture %s", s)
	}
}

// DetectArch reports the runner architecture, the test binary's own. There is
// deliberately no override knob: emulated runs are not supported, and CI covers
// each architecture on a native runner.
func DetectArch() (string, error) {
	return NormalizeArch(runtime.GOARCH)
}

// Matrix expands the combos. $VFOX_VERSION holds the vfox channels separated by
// spaces and defaults to "latest main".
func Matrix() []Combo {
	channels := []string{"latest", "main"}
	if fields := strings.Fields(os.Getenv("VFOX_VERSION")); len(fields) > 0 {
		channels = fields
	}
	combos := make([]Combo, 0, len(channels))
	for _, channel := range channels {
		combos = append(combos, Combo{Vfox: channel})
	}
	return combos
}

// MaxJobs bounds parallel containers; honours $E2E_MAX_JOBS and falls back to
// def when unset or invalid.
func MaxJobs(def int) int {
	if v, ok := os.LookupEnv("E2E_MAX_JOBS"); ok {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n >= 1 {
			return n
		}
	}
	return def
}

// RetryAttempts caps exec retries; honours $E2E_RETRY_ATTEMPTS (default 3).
func RetryAttempts() int {
	if v, ok := os.LookupEnv("E2E_RETRY_ATTEMPTS"); ok && strings.TrimSpace(v) != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
			return n
		}
	}
	return 3
}

// ResolveVersion honours $GRADLE_VERSION, else DefaultVersion. It must differ
// from MirrorVersion and NoSumVersion: the later install would find the first.
func ResolveVersion(t *testing.T) string {
	t.Helper()
	version := strings.TrimSpace(os.Getenv("GRADLE_VERSION"))
	if version == "" {
		return DefaultVersion
	}
	if version == MirrorVersion || version == NoSumVersion {
		t.Fatalf("GRADLE_VERSION=%s is a release the suite installs through a mirror; pick another", version)
	}
	return version
}

// ansiEscape matches the SGR colour sequences vfox prints.
var ansiEscape = regexp.MustCompile(`\x1b\[[0-9;]*m`)

// StripANSI removes SGR colour sequences from command output.
func StripANSI(s string) string {
	return ansiEscape.ReplaceAllString(s, "")
}

// installSuccess matches the "Install gradle@<version> success!" line vfox
// prints with the version PreInstall returned.
var installSuccess = regexp.MustCompile(`Install gradle@(\S+) success!`)

// InstalledVersion extracts the version vfox recorded from `vfox install`
// output, or "" when the line is absent.
func InstalledVersion(output string) string {
	if m := installSuccess.FindStringSubmatch(StripANSI(output)); m != nil {
		return m[1]
	}
	return ""
}

// CheckInstalled asserts that `vfox install gradle@<version>` reported the
// release under the name it was asked for: PreInstall returns the version as
// typed, so the installed name is the spec itself.
func CheckInstalled(t *testing.T, output, version string) {
	t.Helper()
	installed := InstalledVersion(output)
	require.NotEmptyf(t, installed, "vfox install gradle@%s did not report the installed version\n--- output ---\n%s", version, output)
	require.Equalf(t, version, installed, "gradle@%s was installed as %s", version, installed)
}

// usingLatest matches the line vfox prints when it takes `latest` for the
// first entry of Available.
var usingLatest = regexp.MustCompile(`Using latest version: (\S+)`)

// LatestVersion extracts the release vfox took for `latest` from `vfox install`
// output, or "" when the line is absent.
func LatestVersion(output string) string {
	if m := usingLatest.FindStringSubmatch(StripANSI(output)); m != nil {
		return m[1]
	}
	return ""
}

// NoChecksumWarning is what vfox prints for a download that comes with no
// checksum: it skips the verification and trusts the download.
const NoChecksumWarning = "Checksum is not provided, skip verify..."

// verifyingChecksum matches the line vfox prints before it hashes a download,
// with the digest the plugin gave it in hex. The digest is empty where the
// plugin gave none: "Verifying checksum ...".
var verifyingChecksum = regexp.MustCompile(`Verifying checksum ([0-9a-fA-F]*)\.\.\.`)

// SHA256Length is the length of the hex digest Gradle publishes next to each
// distribution (`gradle-8.7-bin.zip.sha256`), which the plugin gives to vfox.
const SHA256Length = 64

// Verification reads from the output of `vfox install` what vfox did about the
// checksum of the download: the digest it verified the download against, empty
// where the plugin gave none, and whether it warned about that.
func Verification(output string) (digest string, warned bool) {
	output = StripANSI(output)
	if m := verifyingChecksum.FindStringSubmatch(output); m != nil {
		digest = m[1]
	}
	return digest, strings.Contains(output, NoChecksumWarning)
}

// CheckVerified asserts that `vfox install` verified the download against a
// SHA-256 digest: vfox printed no warning, and the digest it verified against
// has the length of one. vfox compares it with the hash of the file it
// downloaded and fails the install if they differ, so the install succeeding
// proves the digest is the file's. It returns the digest.
func CheckVerified(t *testing.T, output, version string) string {
	t.Helper()
	digest, warned := Verification(output)
	require.Falsef(t, warned, "vfox install gradle@%s printed %q: the plugin gave vfox no checksum\n--- output ---\n%s",
		version, NoChecksumWarning, output)
	require.Lenf(t, digest, SHA256Length,
		"vfox install gradle@%s did not verify the download against a SHA-256 digest, but %q\n--- output ---\n%s",
		version, digest, output)
	return strings.ToLower(digest)
}

// searchEntry matches one `vfox search gradle` entry: " - <version>", followed
// by " (installed)" for a version that is.
var searchEntry = regexp.MustCompile(`^ - (\S+?)( \(installed\))?$`)

// SearchedVersions extracts the versions from `vfox search gradle` output, in
// the order vfox lists them.
func SearchedVersions(output string) []string {
	var versions []string
	for _, line := range strings.Split(StripANSI(output), "\n") {
		if m := searchEntry.FindStringSubmatch(strings.TrimRight(line, "\r")); m != nil {
			versions = append(versions, m[1])
		}
	}
	return versions
}

// SearchedInstalled reports whether `vfox search gradle` output marks the
// version as installed.
func SearchedInstalled(output, version string) bool {
	for _, line := range strings.Split(StripANSI(output), "\n") {
		if m := searchEntry.FindStringSubmatch(strings.TrimRight(line, "\r")); m != nil && m[1] == version {
			return m[2] != ""
		}
	}
	return false
}

// listedVersion matches one `vfox list gradle` entry: "-> <version>", followed
// by "<— current" for the version in use.
var listedVersion = regexp.MustCompile(`^-> (\S+)`)

// ListedVersions extracts the installed versions from `vfox list gradle`
// output, in the order vfox lists them.
func ListedVersions(output string) []string {
	var versions []string
	for _, line := range strings.Split(StripANSI(output), "\n") {
		if m := listedVersion.FindStringSubmatch(strings.TrimRight(line, "\r")); m != nil {
			versions = append(versions, m[1])
		}
	}
	return versions
}

// Compare orders two Gradle versions by their numbers, part by part, a part a
// version lacks counting as zero (8.14 and 8.14.0 are equal): -1 when a is
// older than b, 1 when newer, 0 when equal. The plugin sorts `vfox search` with
// the same rule (lib/util.lua), and vfox takes `latest` from the first entry,
// so the suite checks the order with its own copy of the rule.
func Compare(a, b string) int {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < max(len(pa), len(pb)); i++ {
		na, nb := part(pa, i), part(pb, i)
		if na != nb {
			if na < nb {
				return -1
			}
			return 1
		}
	}
	return 0
}

func part(parts []string, i int) int {
	if i >= len(parts) {
		return 0
	}
	n, _ := strconv.Atoi(parts[i])
	return n
}

// NewestFirst reports whether the versions run from the newest to the oldest,
// with no release twice.
func NewestFirst(versions []string) bool {
	return slices.IsSortedFunc(versions, func(a, b string) int { return -Compare(a, b) }) &&
		len(slices.Compact(slices.Clone(versions))) == len(versions)
}

// gradleVersion matches the first line of `gradle --version` that names the
// release: "Gradle 9.0.0".
var gradleVersion = regexp.MustCompile(`(?m)^Gradle (\S+)\s*$`)

// GradleVersion extracts the release from `gradle --version` output, or "" when
// no line names one.
func GradleVersion(output string) string {
	if m := gradleVersion.FindStringSubmatch(StripANSI(output)); m != nil {
		return m[1]
	}
	return ""
}

// AskedBogusMirror reports whether `vfox install` output shows the request for
// the checksum going to BogusMirror: the error names the URL, which is the
// mirror, one slash and the file. A second slash would mean the plugin joined
// the value of a mirror that ends in a slash without leaving it out.
func AskedBogusMirror(output, version string) bool {
	output = StripANSI(output)
	return strings.Contains(output, BogusMirror+"/gradle-"+version+"-bin.zip.sha256") &&
		!strings.Contains(output, BogusMirror+"//")
}

// Request is one line of the log of the mirror stand-in.
type Request struct {
	Method string
	URI    string
	Status int
}

// Requests parses the log of the mirror stand-in (tests/e2e/linux/mirror): one
// "<method> <request URI> <status>" line per request, the URI as it was sent.
func Requests(log string) []Request {
	var requests []Request
	for _, line := range strings.Split(log, "\n") {
		fields := strings.Fields(line)
		if len(fields) != 3 {
			continue
		}
		status, err := strconv.Atoi(fields[2])
		if err != nil {
			continue
		}
		requests = append(requests, Request{Method: fields[0], URI: fields[1], Status: status})
	}
	return requests
}

// CheckMirrorServed asserts that the stand-in answered a GET for the release's
// checksum and for its archive, both with 200 and both for the file name alone:
// a request whose URI had a second slash would have been answered 404.
func CheckMirrorServed(t *testing.T, requests []Request, version string) {
	t.Helper()
	checkMirrorAnswers(t, requests, version, 200)
}

// CheckMirrorKeptNoSum asserts the same for a stand-in that keeps no checksums:
// the GET for the release's checksum was answered 404 and the one for its
// archive 200, so the archive came from the mirror and the digest vfox verified
// it against did not.
func CheckMirrorKeptNoSum(t *testing.T, requests []Request, version string) {
	t.Helper()
	checkMirrorAnswers(t, requests, version, 404)
}

func checkMirrorAnswers(t *testing.T, requests []Request, version string, sumStatus int) {
	t.Helper()
	for _, want := range []Request{
		{"GET", "/gradle-" + version + "-bin.zip.sha256", sumStatus},
		{"GET", "/gradle-" + version + "-bin.zip", 200},
	} {
		require.Truef(t, slices.Contains(requests, want), "the mirror was not asked for %s, or did not answer %d: %v", want.URI, want.Status, requests)
	}
}

// ContainerName returns a unique container name per run: the combo slug stays
// greppable in `docker ps`, the random suffix avoids clashes with leftovers
// from killed runs.
func ContainerName(slug string) string {
	var b [4]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("vfox-gradle-e2e-%s-%d", slug, time.Now().UnixNano())
	}
	return "vfox-gradle-e2e-" + slug + "-" + hex.EncodeToString(b[:])
}
