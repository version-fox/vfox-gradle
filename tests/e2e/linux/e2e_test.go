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

// Package linux is the Linux container E2E suite, driven entirely from Go via
// testcontainers-go.
//
// TestE2E builds the image in tests/e2e/linux/Dockerfile once, then runs one
// long-lived container per vfox channel and drives setup -> checks -> install ->
// verify through exec calls (setup.go, install.go, verify.go, mirror.go),
// asserting in Go. Target-independent logic (the matrix, the pinned releases,
// the parsing of output) is reused from the common package.
package linux

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/containerd/platforms"
	specs "github.com/opencontainers/image-spec/specs-go/v1"
	tc "github.com/testcontainers/testcontainers-go"

	client "github.com/moby/moby/client"

	"github.com/version-fox/vfox-gradle/tests/e2e/common"
)

// TestE2E builds the image once, then runs one container per matrix combo.
// Bounded parallelism via t.Parallel + semaphore (like E2E_MAX_JOBS).
//
// Full matrix runs in CI; locally scope it down, e.g.:
// VFOX_VERSION=latest E2E_MAX_JOBS=1 go test -v ./linux/
func TestE2E(t *testing.T) {
	if testing.Short() {
		t.Skip("skip container E2E in short mode")
	}

	arch, err := common.DetectArch()
	if err != nil {
		t.Fatal(err)
	}
	platform := "linux/" + arch
	image := "vfox-gradle-e2e:linux-" + arch

	here, err := filepath.Abs(".")
	if err != nil {
		t.Fatal(err)
	}
	repoRoot := filepath.Join(here, "..", "..", "..")

	ctx := context.Background()
	buildImage(t, ctx, repoRoot, image, platform)

	combos := common.Matrix()
	if len(combos) == 0 {
		t.Fatal("empty matrix: nothing to run")
	}

	sem := make(chan struct{}, maxJobs())
	for _, c := range combos {
		c := c
		t.Run(c.Slug(), func(t *testing.T) {
			t.Parallel()
			sem <- struct{}{}
			defer func() { <-sem }()
			runOne(t, ctx, image, platform, c)
		})
	}
}

// buildImage replicates `docker build --pull --platform $platform
// --file tests/e2e/linux/Dockerfile --tag $image $repoRoot`.
func buildImage(t *testing.T, ctx context.Context, repoRoot, image, platform string) {
	t.Helper()

	provider, err := tc.NewDockerProvider()
	if err != nil {
		t.Fatalf("new docker provider: %v", err)
	}
	t.Cleanup(func() { _ = provider.Close() })

	pf, err := platforms.Parse(platform)
	if err != nil {
		t.Fatalf("invalid platform %s: %v", platform, err)
	}

	tag, err := provider.BuildImage(ctx, &tc.ContainerRequest{
		FromDockerfile: tc.FromDockerfile{
			Context:        repoRoot,
			Dockerfile:     "tests/e2e/linux/Dockerfile",
			Repo:           "vfox-gradle-e2e",
			Tag:            image[strings.LastIndex(image, ":")+1:],
			KeepImage:      true,
			BuildLogWriter: os.Stdout,
			BuildOptionsModifier: func(opts *client.ImageBuildOptions) {
				opts.Platforms = []specs.Platform{pf}
				opts.PullParent = true
			},
		},
	})
	if err != nil {
		t.Fatalf("build image %s: %v", image, err)
	}
	if tag != image {
		t.Fatalf("built tag %s, want %s", tag, image)
	}
}

// runOne starts one long-lived container per combo and drives the whole E2E
// flow through exec calls, asserting in Go. A combo passes when every phase
// exits 0 and the outputs carry the expected markers.
func runOne(t *testing.T, ctx context.Context, image, platform string, c common.Combo) {
	t.Helper()
	prefix := c.Prefix(platform)

	env := map[string]string{
		"VFOX_VERSION": c.Vfox,
	}
	for _, name := range common.PassThroughEnvs {
		if v, ok := os.LookupEnv(name); ok && v != "" {
			env[name] = v
		}
	}

	ctr, err := tc.GenericContainer(ctx, tc.GenericContainerRequest{
		ContainerRequest: tc.ContainerRequest{
			Image:         image,
			ImagePlatform: platform,
			Name:          common.ContainerName(c.Slug()),
			Env:           env,
		},
		Started: true,
	})
	if err != nil {
		t.Fatalf("[%s] start container: %v", prefix, err)
	}
	t.Cleanup(func() {
		_ = ctr.Terminate(context.Background())
	})

	// One overall budget per combo; the CI job timeout stays the outer bound.
	ctx, cancel := context.WithTimeout(ctx, 45*time.Minute)
	defer cancel()

	version := common.ResolveVersion(t)
	machine := strings.TrimSpace(execOK(ctx, t, ctr, "uname --machine"))
	t.Logf("=== vfox %s, gradle@%s, gradle@%s and gradle@%s, %s (%s) ===", c.Vfox, version, common.MirrorVersion, common.NoSumVersion, platform, machine)

	setupVfox(ctx, t, ctr, c.Vfox)
	checkNotes(ctx, t, ctr)

	// The checks that download nothing come first.
	searched := verifySearch(ctx, t, ctr, version, common.MirrorVersion)
	checkMissingRejected(ctx, t, ctr)
	checkBogusMirror(ctx, t, ctr, version)
	checkLatest(ctx, t, ctr, searched[0])
	gateway := startMirror(ctx, t, ctr, 8081, "-checksum-status", "567")
	checkChecksumStatus(ctx, t, ctr, gateway, version, "567")

	// The release from services.gradle.org, verified against the digest Gradle
	// publishes, and then in use.
	digest := installGradle(ctx, t, ctr, version)
	verifyPublishedDigest(ctx, t, ctr, version, digest)
	verifySearchMarks(ctx, t, ctr, version)
	useGradle(ctx, t, ctr, version)
	verifyToolchain(ctx, t, ctr, version)

	// The other release through a mirror that behaves like real ones: the value
	// ends in a slash, and the stand-in answers 404 to a second one; it refuses
	// Go's default User-Agent, which is how vfox downloads unless the plugin
	// names one; and its .sha256 is written as sha256sum writes it.
	proxy := startMirror(ctx, t, ctr, 8080, "-checksum-format", "sha256sum")
	digest = installGradle(ctx, t, ctr, common.MirrorVersion, common.MirrorEnv+"="+proxy.url()+"/")
	common.CheckMirrorServed(t, proxy.requests(ctx, t, ctr), common.MirrorVersion)
	verifyPublishedDigest(ctx, t, ctr, common.MirrorVersion, digest)
	t.Logf("PASS gradle@%s was installed through the mirror at %s", common.MirrorVersion, proxy.url())

	verifySwitch(ctx, t, ctr, version, common.MirrorVersion)

	// A release through a mirror that keeps zips and no .sha256 files, as Tencent
	// Cloud's does for the releases after 8.0.1: the stand-in answers 404 to the
	// checksum. The archive comes from the mirror and the digest from
	// services.gradle.org, and vfox must verify the one against the other, where
	// it used to warn and trust the download.
	bare := startMirror(ctx, t, ctr, 8082, "-checksum-status", "404")
	digest = installGradle(ctx, t, ctr, common.NoSumVersion, common.MirrorEnv+"="+bare.url()+"/")
	common.CheckMirrorKeptNoSum(t, bare.requests(ctx, t, ctr), common.NoSumVersion)
	verifyPublishedDigest(ctx, t, ctr, common.NoSumVersion, digest)
	t.Logf("PASS gradle@%s was installed through the mirror at %s, which keeps no checksums, and verified against the one Gradle publishes", common.NoSumVersion, bare.url())
}
