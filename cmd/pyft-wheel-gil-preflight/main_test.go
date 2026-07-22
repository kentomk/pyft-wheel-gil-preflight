package main

import (
	"bytes"
	"testing"

	"github.com/kentomk/pyft-wheel-gil-preflight/internal/checker"
)

func TestTextGoldenContracts(t *testing.T) {
	tests := []struct {
		name        string
		result      checker.Result
		operational bool
		wantExit    int
		want        string
	}{
		{name: "exit-0", result: fixedResult("pass"), wantExit: 0, want: "PASS fixture.good: GIL remained disabled after import\n"},
		{name: "exit-1", result: fixedResult("violation"), wantExit: 1, want: "PGP001 fixture.good: import re-enabled the GIL\n"},
		{name: "exit-2", result: checker.OperationalResult("fixture.whl", "python3.14t", "fixture.good"), operational: true, wantExit: 2, want: "ERROR: inspection could not complete safely\n"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var output bytes.Buffer
			if err := writeResult(&output, "text", test.result, test.operational); err != nil {
				t.Fatal(err)
			}
			if output.String() != test.want {
				t.Fatalf("output = %q, want %q", output.String(), test.want)
			}
			if got := resultExitCode(test.result, test.operational); got != test.wantExit {
				t.Fatalf("exit = %d, want %d", got, test.wantExit)
			}
		})
	}
}

func TestJSONGoldenContract(t *testing.T) {
	result := fixedResult("violation")
	var output bytes.Buffer
	if err := writeResult(&output, "json", result, false); err != nil {
		t.Fatal(err)
	}
	want := "{\"schemaVersion\":1,\"toolVersion\":\"dev\",\"wheel\":\"fixture-0.0.0-cp314-cp314t-linux_x86_64.whl\",\"python\":\"python3.14t\",\"runtime\":{\"implementation\":\"cpython\",\"version\":\"3.14\",\"gilDisabled\":true,\"soabi\":\"cpython-314t-x86_64-linux-gnu\",\"extensionSuffix\":\".cpython-314t-x86_64-linux-gnu.so\",\"platform\":\"linux-x86_64\",\"machine\":\"x86_64\",\"libc\":\"glibc\",\"libcVersion\":\"2.39\"},\"modules\":[{\"name\":\"fixture.good\",\"discovery\":\"wheel\",\"beforeGilEnabled\":false,\"afterGilEnabled\":true,\"warningObserved\":true,\"status\":\"violation\",\"durationMs\":7}],\"diagnostics\":[{\"ruleId\":\"PGP001\",\"severity\":\"error\",\"module\":\"fixture.good\",\"message\":\"import re-enabled the GIL in a free-threaded interpreter\",\"remediation\":\"verify thread safety before declaring GIL-free support\"}],\"summary\":{\"checked\":1,\"violations\":1,\"errors\":0}}\n"
	if output.String() != want {
		t.Fatalf("JSON contract changed:\n%s", output.String())
	}
}

func fixedResult(status string) checker.Result {
	result := checker.Result{
		SchemaVersion: 1,
		ToolVersion:   "dev",
		Wheel:         "fixture-0.0.0-cp314-cp314t-linux_x86_64.whl",
		Python:        "python3.14t",
		Runtime: checker.Runtime{
			Implementation: "cpython", Version: "3.14", GILDisabled: true,
			SOABI: "cpython-314t-x86_64-linux-gnu", ExtensionSuffix: ".cpython-314t-x86_64-linux-gnu.so",
			Platform: "linux-x86_64", Machine: "x86_64",
			Libc: "glibc", LibcVersion: "2.39",
		},
		Modules: []checker.Module{{Name: "fixture.good", Discovery: "wheel", AfterGILEnabled: status == "violation", WarningObserved: status == "violation", Status: status, DurationMS: 7}},
		Summary: checker.Summary{Checked: 1},
	}
	if status == "violation" {
		result.Diagnostics = []checker.Diagnostic{{RuleID: "PGP001", Severity: "error", Module: "fixture.good", Message: "import re-enabled the GIL in a free-threaded interpreter", Remediation: "verify thread safety before declaring GIL-free support"}}
		result.Summary.Violations = 1
	} else {
		result.Diagnostics = []checker.Diagnostic{}
	}
	return result
}
