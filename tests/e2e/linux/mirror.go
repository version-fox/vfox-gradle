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
	"testing"

	tc "github.com/testcontainers/testcontainers-go"

	"github.com/version-fox/vfox-gradle/tests/e2e/common"
)

// mirror is a stand-in for a Gradle mirror running in a container (see
// ./mirror): it listens on the container's loopback, so VFOX_GRADLE_MIRRORS can
// name it with plain http://, and it logs the requests it gets.
type mirror struct {
	port int
}

// url is what VFOX_GRADLE_MIRRORS is set to for the stand-in.
func (m mirror) url() string {
	return fmt.Sprintf("http://127.0.0.1:%d", m.port)
}

func (m mirror) logPath() string {
	return fmt.Sprintf("/tmp/gradle-mirror-%d.log", m.port)
}

// startMirror starts the stand-in on port, with the flags given, and returns
// once it answers. Its output is redirected: the exec would otherwise wait for
// a process that holds its pipes open.
func startMirror(ctx context.Context, t *testing.T, ctr tc.Container, port int, flags ...string) mirror {
	t.Helper()
	m := mirror{port: port}
	args := ""
	for _, flag := range flags {
		args += " " + shQuote(flag)
	}
	execOK(ctx, t, ctr, fmt.Sprintf(`set -e
nohup gradle-mirror -addr 127.0.0.1:%[1]d -log %[2]s%[3]s < /dev/null > /tmp/gradle-mirror-%[1]d.out 2>&1 &
# Up once curl gets any answer from it.
for i in $(seq 50); do curl --silent --output /dev/null %[4]s/ && exit 0; sleep 0.2; done
cat /tmp/gradle-mirror-%[1]d.out
exit 1`, port, m.logPath(), args, m.url()))
	return m
}

// requests reads what the stand-in has been asked so far.
func (m mirror) requests(ctx context.Context, t *testing.T, ctr tc.Container) []common.Request {
	t.Helper()
	return common.Requests(execOK(ctx, t, ctr, "cat "+m.logPath()))
}
