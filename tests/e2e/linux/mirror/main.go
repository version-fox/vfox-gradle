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

// Command mirror is the stand-in for a Gradle mirror that the Linux E2E suite
// starts in a container and points VFOX_GRADLE_MIRRORS at.
//
// A mirror keeps the files of services.gradle.org/distributions under its own
// prefix: <mirror>/gradle-<version>-bin.zip and the .sha256 next to it. This one
// answers exactly those two paths, by asking services.gradle.org (and following
// its redirects) for the same file, and logs each request as
//
//	<method> <request URI> <status>
//
// with the URI as it came in. The suite reads the log to see which files the
// plugin asked a mirror for. Any other path, such as one with a second slash
// ("//gradle-8.7-bin.zip"), is answered 404 rather than cleaned up, so a plugin
// that joins a mirror ending in a slash badly cannot pass unnoticed.
//
// It behaves like the mirrors that real installs met:
//
//   - A request whose User-Agent is Go's default, Go-http-client/..., is
//     answered 403 with a page of HTML. vfox downloads an archive as
//     Go-http-client unless the plugin names another agent, and it saves
//     whatever it gets, so the page ends as "Checksum error". Huawei Cloud's
//     mirror of Gradle behaves so (2026-11-03).
//   - With -checksum-format sha256sum the .sha256 files are written the way
//     `sha256sum <file> > <file>.sha256` writes them, "<digest>  <file>" and a
//     newline, where Gradle's hold the digest alone. vfox compares the digest
//     with the hash of the download as it stands, so a plugin that passes the
//     text on makes a good download fail.
//   - With -checksum-status it answers every .sha256 request with that status and
//     asks nobody, the way a gateway in front of a mirror can.
package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
)

// file matches the two paths of a release a mirror serves; the first group is
// the file name, the second is ".sha256" for the digest.
var file = regexp.MustCompile(`^/(gradle-[0-9][0-9A-Za-z.\-]*-bin\.zip(\.sha256)?)$`)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "address to listen on")
	logPath := flag.String("log", "mirror.log", "file the requests are appended to")
	upstream := flag.String("upstream", "https://services.gradle.org/distributions", "where the files come from")
	checksumStatus := flag.Int("checksum-status", 0, "answer every .sha256 request with this status instead of the file")
	checksumFormat := flag.String("checksum-format", "plain", `how the .sha256 files are written: "plain", the digest alone as Gradle does, or "sha256sum"`)
	flag.Parse()
	if *checksumFormat != "plain" && *checksumFormat != "sha256sum" {
		log.Fatalf("unknown -checksum-format %q", *checksumFormat)
	}

	out, err := os.OpenFile(*logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		log.Fatal(err)
	}
	defer out.Close()

	var mu sync.Mutex
	record := func(r *http.Request, status int) {
		mu.Lock()
		defer mu.Unlock()
		fmt.Fprintf(out, "%s %s %d\n", r.Method, r.RequestURI, status)
	}

	// Not a ServeMux: it would clean "//" out of the path and redirect.
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		match := file.FindStringSubmatch(r.URL.Path)
		if match == nil || (r.Method != http.MethodGet && r.Method != http.MethodHead) {
			http.NotFound(w, r)
			record(r, http.StatusNotFound)
			return
		}
		if strings.HasPrefix(r.UserAgent(), "Go-http-client/") {
			http.Error(w, "<html><body>403 Forbidden</body></html>", http.StatusForbidden)
			record(r, http.StatusForbidden)
			return
		}
		isChecksum := match[2] != ""
		if isChecksum && *checksumStatus != 0 {
			w.WriteHeader(*checksumStatus)
			fmt.Fprintln(w, "answered by the mirror stand-in")
			record(r, *checksumStatus)
			return
		}
		req, err := http.NewRequestWithContext(r.Context(), r.Method, *upstream+"/"+match[1], nil)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			record(r, http.StatusInternalServerError)
			return
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			record(r, http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		if isChecksum && *checksumFormat == "sha256sum" && resp.StatusCode == http.StatusOK {
			digest, err := io.ReadAll(resp.Body)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadGateway)
				record(r, http.StatusBadGateway)
				return
			}
			text := fmt.Sprintf("%s  %s\n", strings.TrimSpace(string(digest)), strings.TrimSuffix(match[1], ".sha256"))
			w.Header().Set("Content-Type", "text/plain")
			w.Header().Set("Content-Length", strconv.Itoa(len(text)))
			w.WriteHeader(http.StatusOK)
			if r.Method == http.MethodGet {
				_, _ = io.WriteString(w, text)
			}
			record(r, http.StatusOK)
			return
		}

		for _, name := range []string{"Content-Type", "Content-Length"} {
			if v := resp.Header.Get(name); v != "" {
				w.Header().Set(name, v)
			}
		}
		w.WriteHeader(resp.StatusCode)
		if r.Method == http.MethodGet {
			_, _ = io.Copy(w, resp.Body)
		}
		record(r, resp.StatusCode)
	})

	log.Fatal(http.ListenAndServe(*addr, handler))
}
