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

package common

import (
	"slices"
	"strings"
	"testing"
)

func vfoxChannels(combos []Combo) []string {
	channels := make([]string, 0, len(combos))
	for _, c := range combos {
		channels = append(channels, c.Vfox)
	}
	return channels
}

// By default both vfox channels run.
func TestMatrixDefault(t *testing.T) {
	t.Setenv("VFOX_VERSION", "")
	if got := vfoxChannels(Matrix()); !slices.Equal(got, []string{"latest", "main"}) {
		t.Fatalf("channels = %v, want [latest main]", got)
	}
}

func TestMatrixExplicit(t *testing.T) {
	t.Setenv("VFOX_VERSION", "main  latest")
	if got := vfoxChannels(Matrix()); !slices.Equal(got, []string{"main", "latest"}) {
		t.Fatalf("channels = %v, want [main latest]", got)
	}
}

func TestSlugAndPrefix(t *testing.T) {
	c := Combo{Vfox: "latest"}
	if got := c.Slug(); got != "latest" {
		t.Errorf("Slug = %q, want latest", got)
	}
	if got := (Combo{Vfox: "v1.0/rc 1"}).Slug(); got != "v1_0_rc_1" {
		t.Errorf("Slug = %q, want v1_0_rc_1", got)
	}
	if got := c.Prefix("linux/arm64"); got != "vfox latest, linux/arm64" {
		t.Errorf("Prefix = %q", got)
	}
}

func TestNormalizeArch(t *testing.T) {
	for in, want := range map[string]string{"x86_64": "amd64", "AMD64": "amd64", "x64": "amd64", "aarch64": "arm64", "arm64": "arm64"} {
		got, err := NormalizeArch(in)
		if err != nil || got != want {
			t.Errorf("NormalizeArch(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	if _, err := NormalizeArch("riscv64"); err == nil {
		t.Error("NormalizeArch(riscv64) must fail")
	}
	if arch, err := DetectArch(); err != nil || (arch != "amd64" && arch != "arm64") {
		t.Errorf("DetectArch = %q, %v", arch, err)
	}
}

func TestMaxJobs(t *testing.T) {
	for in, want := range map[string]int{"": 3, "0": 3, "-1": 3, "x": 3, "1": 1, " 4 ": 4} {
		t.Setenv("E2E_MAX_JOBS", in)
		if got := MaxJobs(3); got != want {
			t.Errorf("MaxJobs with %q = %d, want %d", in, got, want)
		}
	}
}

func TestRetryAttemptsDefault(t *testing.T) {
	t.Setenv("E2E_RETRY_ATTEMPTS", "")
	if got := RetryAttempts(); got != 3 {
		t.Errorf("RetryAttempts = %d, want 3", got)
	}
	t.Setenv("E2E_RETRY_ATTEMPTS", "5")
	if got := RetryAttempts(); got != 5 {
		t.Errorf("RetryAttempts = %d, want 5", got)
	}
}

func TestResolveVersion(t *testing.T) {
	t.Setenv("GRADLE_VERSION", "")
	if got := ResolveVersion(t); got != DefaultVersion {
		t.Errorf("ResolveVersion = %q, want %q", got, DefaultVersion)
	}
	t.Setenv("GRADLE_VERSION", "8.14.3")
	if got := ResolveVersion(t); got != "8.14.3" {
		t.Errorf("ResolveVersion = %q, want 8.14.3", got)
	}
}

// The two pinned releases are two releases, one written each way Gradle names
// them, and none of the names no release has is one of them.
func TestPins(t *testing.T) {
	if DefaultVersion == MirrorVersion {
		t.Fatalf("both pins are %s: the second install would find the first", DefaultVersion)
	}
	if !strings.HasSuffix(DefaultVersion, ".0") || strings.Count(MirrorVersion, ".") != 1 {
		t.Errorf("pins %s and %s should be one written with the trailing .0 and one without", DefaultVersion, MirrorVersion)
	}
	for _, missing := range MissingVersions {
		if missing == DefaultVersion || missing == MirrorVersion {
			t.Errorf("%s is pinned and listed as missing", missing)
		}
	}
}

func TestInstalledVersion(t *testing.T) {
	out := "Preinstalling gradle@8.7...\n\x1b[32mInstall gradle@8.7 success!\x1b[0m \nPlease use `vfox use gradle@8.7` to use it.\n"
	if got := InstalledVersion(out); got != "8.7" {
		t.Errorf("InstalledVersion = %q, want 8.7", got)
	}
	if got := InstalledVersion("failed to install gradle\n"); got != "" {
		t.Errorf("InstalledVersion of a failure = %q, want empty", got)
	}
}

func TestLatestVersion(t *testing.T) {
	out := "\x1b[0mUsing latest version: 9.8.2\nPreinstalling gradle@9.8.2...\n"
	if got := LatestVersion(out); got != "9.8.2" {
		t.Errorf("LatestVersion = %q, want 9.8.2", got)
	}
	if got := LatestVersion("Preinstalling gradle@8.7...\n"); got != "" {
		t.Errorf("LatestVersion = %q, want empty", got)
	}
}

func TestVerification(t *testing.T) {
	digest := "544c35d6bd849ae8a5ed0bcea39ba677dc40f49df7d1835561582da2009b961d"
	got, warned := Verification("Downloading... 100%\nVerifying checksum " + digest + "...\nUnpacking x.zip...\n")
	if got != digest || warned {
		t.Errorf("Verification = %q, %v; want the digest and no warning", got, warned)
	}
	got, warned = Verification("Verifying checksum ...\nWARNING: " + NoChecksumWarning + "\n")
	if got != "" || !warned {
		t.Errorf("Verification without a checksum = %q, %v; want empty and a warning", got, warned)
	}
	if got, warned = Verification("nothing about checksums\n"); got != "" || warned {
		t.Errorf("Verification of unrelated output = %q, %v", got, warned)
	}
}

func TestCheckVerified(t *testing.T) {
	digest := "544C35D6BD849AE8A5ED0BCEA39BA677DC40F49DF7D1835561582DA2009B961D"
	if got := CheckVerified(t, "Verifying checksum "+digest+"...\n", "8.7"); got != strings.ToLower(digest) {
		t.Errorf("CheckVerified = %q, want the digest lower-cased", got)
	}
}

func TestCheckInstalled(t *testing.T) {
	CheckInstalled(t, "Install gradle@9.0.0 success!\n", "9.0.0")
}

func TestSearchedVersions(t *testing.T) {
	out := "Available versions:\n - 9.8.2 (installed)\n - 9.8.1\n - 8.14\n - 0.7\r\n"
	want := []string{"9.8.2", "9.8.1", "8.14", "0.7"}
	if got := SearchedVersions(out); !slices.Equal(got, want) {
		t.Errorf("SearchedVersions = %v, want %v", got, want)
	}
	if !SearchedInstalled(out, "9.8.2") {
		t.Error("9.8.2 is installed")
	}
	if SearchedInstalled(out, "9.8.1") || SearchedInstalled(out, "1.0") {
		t.Error("9.8.1 is not installed, and 1.0 is not listed")
	}
}

func TestListedVersions(t *testing.T) {
	out := "-> 9.8.2 <— current\n-> 8.7\n-> 8.14\n"
	if got := ListedVersions(out); !slices.Equal(got, []string{"9.8.2", "8.7", "8.14"}) {
		t.Errorf("ListedVersions = %v", got)
	}
	if got := ListedVersions("no available version\n"); len(got) != 0 {
		t.Errorf("ListedVersions of an empty list = %v", got)
	}
}

func TestCompare(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"8.14", "8.7", 1},
		{"8.7", "8.14", -1},
		{"10.0", "9.8.2", 1},
		{"9.0.0", "8.14.6", 1},
		{"8.14", "8.14.0", 0},
		{"9.0", "9.0.0", 0},
		{"8.14", "8.14.1", -1},
		{"0.7", "0.9.2", -1},
		{"8.7", "8.7", 0},
	}
	for _, c := range cases {
		if got := Compare(c.a, c.b); got != c.want {
			t.Errorf("Compare(%s, %s) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestNewestFirst(t *testing.T) {
	if !NewestFirst([]string{"9.8.2", "9.8.1", "9.0.0", "8.14.6", "8.14", "8.7", "0.7"}) {
		t.Error("a list from the newest to the oldest is newest first")
	}
	if NewestFirst([]string{"9.8.2", "8.14.6", "9.8.1"}) {
		t.Error("the page order of gradle.org is not newest first")
	}
	if NewestFirst([]string{"9.8.2", "9.8.2", "9.8.1"}) {
		t.Error("a release listed twice is not newest first")
	}
	if NewestFirst([]string{"8.7", "8.14"}) {
		t.Error("8.7 is older than 8.14")
	}
}

func TestGradleVersion(t *testing.T) {
	out := "\n------------------------------------------------------------\nGradle 8.7\n------------------------------------------------------------\n\nBuild time:    2024-03-22 15:52:46 UTC\nKotlin:        1.9.22\n"
	if got := GradleVersion(out); got != "8.7" {
		t.Errorf("GradleVersion = %q, want 8.7", got)
	}
	if got := GradleVersion("Welcome to Gradle 8.7!\n"); got != "" {
		t.Errorf("GradleVersion of a sentence = %q, want empty", got)
	}
}

func TestAskedBogusMirror(t *testing.T) {
	asked := `plugin [PreInstall] method error: hooks/pre_install.lua:39: HTTP request error: Get "https://invalid.example.invalid/gradle-8.7-bin.zip.sha256": dial tcp: lookup invalid.example.invalid: no such host`
	if !AskedBogusMirror(asked, "8.7") {
		t.Error("the error names the checksum URL at the mirror")
	}
	if AskedBogusMirror(strings.Replace(asked, "invalid/gradle", "invalid//gradle", 1), "8.7") {
		t.Error("a second slash is the plugin joining the value badly")
	}
	if AskedBogusMirror("Install gradle@8.7 success!", "8.7") {
		t.Error("an install that succeeded never asked the mirror")
	}
	if AskedBogusMirror(asked, "9.0.0") {
		t.Error("the error names another release")
	}
}

func TestRequests(t *testing.T) {
	log := "GET /gradle-8.7-bin.zip.sha256 200\nGET /gradle-8.7-bin.zip 200\nGET //gradle-8.7-bin.zip 404\nbroken\nGET /x notastatus\n\n"
	want := []Request{
		{"GET", "/gradle-8.7-bin.zip.sha256", 200},
		{"GET", "/gradle-8.7-bin.zip", 200},
		{"GET", "//gradle-8.7-bin.zip", 404},
	}
	if got := Requests(log); !slices.Equal(got, want) {
		t.Errorf("Requests = %v, want %v", got, want)
	}
	CheckMirrorServed(t, want, "8.7")
}

func TestContainerName(t *testing.T) {
	a, b := ContainerName("latest"), ContainerName("latest")
	if !strings.HasPrefix(a, "vfox-gradle-e2e-latest-") || a == b {
		t.Errorf("names %q and %q must share the prefix and differ", a, b)
	}
}

func TestStripANSI(t *testing.T) {
	if got := StripANSI("\x1b[94m9.8.2\x1b[0m"); got != "9.8.2" {
		t.Errorf("StripANSI = %q", got)
	}
}
