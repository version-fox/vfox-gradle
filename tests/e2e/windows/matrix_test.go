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
	"strings"
	"testing"
)

func TestMaxJobsDefault(t *testing.T) {
	t.Setenv("E2E_MAX_JOBS", "")
	// empty means unset-equivalent for maxJobs (Atoi fails -> default 2)
	if got := maxJobs(); got != 2 {
		t.Errorf("maxJobs = %d, want 2", got)
	}
	t.Setenv("E2E_MAX_JOBS", "0")
	if got := maxJobs(); got != 2 {
		t.Errorf("maxJobs(0) = %d, want 2 (clamped to default)", got)
	}
}

func TestPwshQuote(t *testing.T) {
	if got := pwshQuote(`C:\a\b`); got != `'C:\a\b'` {
		t.Errorf("pwshQuote = %q", got)
	}
	if got := pwshQuote(`it's`); got != `'it''s'` {
		t.Errorf("pwshQuote escape = %q", got)
	}
}

// Two spellings of one Windows path compare equal, in either case.
func TestWindowsPath(t *testing.T) {
	a := windowsPath(`C:\Users\John Doe\.vfox\sdks\gradle/bin\gradle.bat`)
	b := windowsPath(`c:\users\john doe\.vfox\sdks\gradle\bin\GRADLE.BAT`)
	if a != b {
		t.Errorf("windowsPath: %q != %q", a, b)
	}
}

// The script that checks the toolchain quotes the directory it builds in, which
// holds no quote, and keeps the build script whole: a single-quoted PowerShell
// string takes the Groovy's `$` and `"` as they are and needs only its own
// quote doubled.
func TestToolchainScript(t *testing.T) {
	script := toolchainScript(`C:\Users\O'Neil\tmp\e2e-gradle`)
	for _, want := range []string{
		"gradle --version\n",
		`'GRADLE_HOME=' + $env:GRADLE_HOME`,
		`'GRADLE_BIN_WANT=' + [IO.Path]::GetFullPath((Join-Path $env:GRADLE_HOME 'bin\gradle.bat'))`,
		`New-Item -ItemType Directory -Force -Path 'C:\Users\O''Neil\tmp\e2e-gradle' | Out-Null`,
		`Set-Content -Path 'C:\Users\O''Neil\tmp\e2e-gradle\settings.gradle' -Value 'rootProject.name = ''e2e'''`,
		`println "hello from Gradle ${gradle.gradleVersion}"`,
		`Set-Location -LiteralPath 'C:\Users\O''Neil\tmp\e2e-gradle'`,
	} {
		if !strings.Contains(script, want) {
			t.Errorf("the toolchain script lacks %q:\n%s", want, script)
		}
	}
	if !strings.HasSuffix(script, "\ngradle --quiet --no-daemon hello") {
		t.Errorf("the toolchain script must end with the build:\n%s", script)
	}
	// The build script's own single quotes are doubled once and only once.
	if strings.Count(script, `tasks.register(''hello'')`) != 1 {
		t.Errorf("the quotes of the build script are not doubled:\n%s", script)
	}
}
