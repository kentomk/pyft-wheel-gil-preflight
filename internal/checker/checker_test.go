package checker

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestCheckPassAndViolation(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixture is POSIX-only")
	}
	wheel := makeWheel(t, map[string]string{"fixture.txt": "original fixture"})
	pass := fakePython(t, `{"before":false,"after":false,"warning":false}`)
	result, err := Check(Options{Wheel: wheel, Python: pass, Modules: []string{"goodext"}, Timeout: time.Second})
	if err != nil || result.Summary.Violations != 0 || result.Modules[0].Status != "pass" {
		t.Fatalf("pass result = %#v, err = %v", result, err)
	}

	bad := fakePython(t, `{"before":false,"after":true,"warning":true}`)
	result, err = Check(Options{Wheel: wheel, Python: bad, Modules: []string{"badext"}, Timeout: time.Second})
	if err != nil || len(result.Diagnostics) != 1 || result.Diagnostics[0].RuleID != "PGP001" {
		t.Fatalf("violation result = %#v, err = %v", result, err)
	}
}

func TestRejectsEnabledBaselineAndUnsafeArchive(t *testing.T) {
	wheel := makeWheel(t, map[string]string{"fixture.txt": "x"})
	enabled := fakePython(t, `{"before":true,"after":true,"warning":false}`)
	if _, err := Check(Options{Wheel: wheel, Python: enabled, Modules: []string{"badext"}, Timeout: time.Second}); err == nil {
		t.Fatal("enabled baseline was accepted")
	}
	unsafe := makeWheel(t, map[string]string{"../escape": "x"})
	if _, err := Check(Options{Wheel: unsafe, Python: enabled, Modules: []string{"badext"}, Timeout: time.Second}); err == nil {
		t.Fatal("unsafe wheel path was accepted")
	}
}

func TestWheelTagCompatibility(t *testing.T) {
	runtimeInfo := Runtime{Version: "3.14", Platform: "linux-x86_64", Machine: "x86_64", Libc: "glibc", LibcVersion: "2.39"}
	accepted := []string{
		"fixture-0.0.0-cp314-cp314t-linux_x86_64.whl",
		"fixture-0.0.0-cp314-cp314t-manylinux_2_28_x86_64.whl",
	}
	for _, wheel := range accepted {
		if err := validateWheelTag(wheel, runtimeInfo); err != nil {
			t.Fatalf("%s was rejected: %v", wheel, err)
		}
	}
	rejected := []string{
		"fixture.whl",
		"fixture-0.0.0-cp313-cp313t-linux_x86_64.whl",
		"fixture-0.0.0-cp314-cp314-linux_x86_64.whl",
		"fixture-0.0.0-cp314-cp314t-linux_aarch64.whl",
		"fixture-0.0.0-cp314-cp314t-any.whl",
		"fixture-0.0.0-cp314-cp314t-manylinux_2_40_x86_64.whl",
		"fixture-0.0.0-cp314-cp314t-musllinux_1_2_x86_64.whl",
	}
	for _, wheel := range rejected {
		if err := validateWheelTag(wheel, runtimeInfo); err == nil {
			t.Fatalf("%s was accepted", wheel)
		}
	}
}

func TestArchiveEntryCountBoundary(t *testing.T) {
	entries := make(map[string]string, maxArchiveEntries)
	for i := 0; i < maxArchiveEntries; i++ {
		entries[fmt.Sprintf("data/%04d.txt", i)] = "x"
	}
	atLimit := makeWheel(t, entries)
	if err := extractWheel(atLimit, t.TempDir()); err != nil {
		t.Fatalf("archive at entry limit was rejected: %v", err)
	}
	entries["data/overflow.txt"] = "x"
	overLimit := makeWheel(t, entries)
	if err := extractWheel(overLimit, t.TempDir()); err == nil {
		t.Fatal("archive above entry limit was accepted")
	}
}

func TestArchiveExpandedSizeBoundary(t *testing.T) {
	if total, err := addExpandedSize(maxExtractedBytes-1, 1); err != nil || total != maxExtractedBytes {
		t.Fatalf("exact expanded-size limit failed: total=%d err=%v", total, err)
	}
	if _, err := addExpandedSize(maxExtractedBytes, 1); err == nil {
		t.Fatal("expanded size above limit was accepted")
	}
	if _, err := addExpandedSize(0, maxExtractedBytes+1); err == nil {
		t.Fatal("single entry above limit was accepted")
	}
}

func TestDiscoverModules(t *testing.T) {
	unsupported := makeWheel(t, map[string]string{
		"fixture-0.0.0.data/purelib/data_native.cpython-314.so": "unsupported",
	})
	if _, err := discoverModules(unsupported); err == nil {
		t.Fatal("native .data layout was accepted")
	}

	wheel := makeWheel(t, map[string]string{
		"badext.cpython-314t-aarch64-linux-gnu.so":  "native",
		"fixture_pkg/__init__.py":                   "pure",
		"fixture_pkg/goodext.abi3.so":               "native",
		"_goodext.pyd":                              "native",
		"fixture.libs/libhelper.so":                 "vendored",
		"fixture-0.0.0.dist-info/native-looking.so": "metadata",
		"pure.py": "pure",
	})
	modules, err := discoverModules(wheel)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"_goodext", "badext", "fixture_pkg.goodext"}
	if len(modules) != len(want) {
		t.Fatalf("modules = %#v", modules)
	}
	for i := range want {
		if modules[i] != want[i] {
			t.Fatalf("modules = %#v", modules)
		}
	}
}

func TestDiscoveryFailsClosed(t *testing.T) {
	noNative := makeWheel(t, map[string]string{"package/__init__.py": "pure"})
	if _, err := discoverModules(noNative); err == nil {
		t.Fatal("wheel without native modules was accepted")
	}
	ambiguous := makeWheel(t, map[string]string{
		"module.abi3.so":                 "one",
		"module.cpython-314t-aarch64.so": "two",
	})
	if _, err := discoverModules(ambiguous); err == nil {
		t.Fatal("ambiguous duplicate module was accepted")
	}
	if err := validateExplicitModules([]string{"good", "bad-name"}); err == nil {
		t.Fatal("invalid explicit module was accepted")
	}
	if err := validateExplicitModules([]string{"same", "same"}); err == nil {
		t.Fatal("duplicate explicit module was accepted")
	}
}

func TestFailureSafety(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX process fixtures")
	}
	wheel := makeWheel(t, map[string]string{"fixture.txt": "x"})
	tests := []struct {
		name    string
		script  string
		timeout time.Duration
	}{
		{name: "import-error", script: "exit 3", timeout: time.Second},
		{name: "signal", script: "kill -TERM $$", timeout: time.Second},
		{name: "timeout", script: "sleep 60", timeout: 50 * time.Millisecond},
		{name: "stdout-flood", script: "head -c 20000 /dev/zero; sleep 60", timeout: time.Second},
		{name: "stderr-secret", script: "printf 'PYFT_SECRET_CANARY' >&2; exit 3", timeout: time.Second},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			python := fakePythonScript(t, test.script)
			started := time.Now()
			if _, err := Check(Options{Wheel: wheel, Python: python, Modules: []string{"fixture"}, Timeout: test.timeout}); err == nil {
				t.Fatal("failure fixture was accepted")
			}
			if elapsed := time.Since(started); elapsed > 2*time.Second {
				t.Fatalf("failure cleanup took %s", elapsed)
			}
		})
	}
	encoded, err := json.Marshal(OperationalResult("wheel.whl", "python", "fixture"))
	if err != nil || strings.Contains(string(encoded), "PYFT_SECRET_CANARY") {
		t.Fatal("secret canary reached operational report")
	}
}

func TestDescendantPipeHoldIsKilled(t *testing.T) {
	if runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
		t.Skip("process-group cleanup is supported on Linux and macOS")
	}
	wheel := makeWheel(t, map[string]string{"fixture.txt": "x"})
	pidFile := filepath.Join(t.TempDir(), "child.pid")
	script := fmt.Sprintf("sleep 60 & child=$!; printf '%%s' \"$child\" > %s; printf '%%s\\n' '{\"before\":false,\"after\":false,\"warning\":false}'", shellQuote(pidFile))
	python := fakePythonScript(t, script)
	started := time.Now()
	result, err := Check(Options{Wheel: wheel, Python: python, Modules: []string{"fixture"}, Timeout: time.Second})
	if err != nil || result.Modules[0].Status != "pass" {
		t.Fatalf("descendant fixture result = %#v, err = %v", result, err)
	}
	if elapsed := time.Since(started); elapsed > 2*time.Second {
		t.Fatalf("descendant cleanup took %s", elapsed)
	}
	rawPID, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(string(rawPID))
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(time.Second)
	for syscall.Kill(pid, 0) == nil && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if syscall.Kill(pid, 0) == nil {
		t.Fatalf("descendant process %d remains alive", pid)
	}
}

func fakePython(t *testing.T, payload string) string {
	t.Helper()
	return fakePythonScript(t, "printf '%s\\n' '"+payload+"'")
}

func fakePythonScript(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "python")
	runtimePayload := `{"implementation":"cpython","version":"3.14","gilDisabled":true,"soabi":"cpython-314t-x86_64-linux-gnu","extensionSuffix":".cpython-314t-x86_64-linux-gnu.so","platform":"linux-x86_64","machine":"x86_64","libc":"glibc","libcVersion":"2.39"}`
	content := "#!/bin/sh\nif [ \"$#\" -eq 3 ]; then printf '%s\\n' '" + runtimePayload + "'; exit 0; fi\n" + body + "\n"
	if err := os.WriteFile(path, []byte(content), 0o700); err != nil {
		t.Fatal(err)
	}
	return path
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func makeWheel(t *testing.T, files map[string]string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fixture-0.0.0-cp314-cp314t-linux_x86_64.whl")
	output, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	w := zip.NewWriter(output)
	for name, content := range files {
		entry, err := w.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := entry.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	if err := output.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}
