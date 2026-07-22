package checker

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	maxArchiveEntries = 1024
	maxExtractedBytes = 64 << 20
	maxModules        = 256
)

var ErrOperational = errors.New("operational failure")

type Options struct {
	Wheel   string
	Python  string
	Modules []string
	Timeout time.Duration
}

type Result struct {
	SchemaVersion int          `json:"schemaVersion"`
	ToolVersion   string       `json:"toolVersion"`
	Wheel         string       `json:"wheel"`
	Python        string       `json:"python"`
	Runtime       Runtime      `json:"runtime"`
	Modules       []Module     `json:"modules"`
	Diagnostics   []Diagnostic `json:"diagnostics"`
	Summary       Summary      `json:"summary"`
}

type Runtime struct {
	Implementation  string `json:"implementation"`
	Version         string `json:"version"`
	GILDisabled     bool   `json:"gilDisabled"`
	SOABI           string `json:"soabi"`
	ExtensionSuffix string `json:"extensionSuffix"`
	Platform        string `json:"platform"`
	Machine         string `json:"machine"`
	Libc            string `json:"libc,omitempty"`
	LibcVersion     string `json:"libcVersion,omitempty"`
}

type Module struct {
	Name             string `json:"name"`
	Discovery        string `json:"discovery"`
	BeforeGILEnabled bool   `json:"beforeGilEnabled"`
	AfterGILEnabled  bool   `json:"afterGilEnabled"`
	WarningObserved  bool   `json:"warningObserved"`
	Status           string `json:"status"`
	DurationMS       int64  `json:"durationMs"`
}

type Diagnostic struct {
	RuleID      string `json:"ruleId"`
	Severity    string `json:"severity"`
	Module      string `json:"module"`
	Message     string `json:"message"`
	Remediation string `json:"remediation"`
}

type Summary struct {
	Checked    int `json:"checked"`
	Violations int `json:"violations"`
	Errors     int `json:"errors"`
}

type probeResult struct {
	Before  bool `json:"before"`
	After   bool `json:"after"`
	Warning bool `json:"warning"`
}

func OperationalResult(wheel, python, module string) Result {
	if module == "" {
		module = "<automatic>"
	}
	return Result{
		SchemaVersion: 1,
		ToolVersion:   "dev",
		Wheel:         wheel,
		Python:        python,
		Runtime:       Runtime{},
		Modules:       []Module{{Name: module, Discovery: "unknown", Status: "error"}},
		Diagnostics:   []Diagnostic{},
		Summary:       Summary{Errors: 1},
	}
}

func Check(opts Options) (Result, error) {
	if opts.Wheel == "" || opts.Python == "" || opts.Timeout <= 0 {
		return Result{}, ErrOperational
	}
	runtimeInfo, err := probeRuntime(opts.Python, opts.Timeout)
	if err != nil || validateWheelTag(opts.Wheel, runtimeInfo) != nil {
		return Result{}, ErrOperational
	}
	temp, err := os.MkdirTemp("", "pyft-wheel-gil-preflight-")
	if err != nil {
		return Result{}, ErrOperational
	}
	defer os.RemoveAll(temp)
	if err := extractWheel(opts.Wheel, temp); err != nil {
		return Result{}, ErrOperational
	}

	modules := append([]string(nil), opts.Modules...)
	discovery := "explicit"
	if len(modules) == 0 {
		modules, err = discoverModules(opts.Wheel)
		if err != nil {
			return Result{}, ErrOperational
		}
		discovery = "wheel"
	} else {
		if err := validateExplicitModules(modules); err != nil {
			return Result{}, ErrOperational
		}
		sort.Strings(modules)
	}
	if len(modules) == 0 || len(modules) > maxModules {
		return Result{}, ErrOperational
	}

	globalCtx, globalCancel := context.WithTimeout(context.Background(), time.Minute)
	defer globalCancel()
	results := make([]Module, 0, len(modules))
	diagnostics := make([]Diagnostic, 0)
	for _, moduleName := range modules {
		probe, duration, err := runProbe(globalCtx, opts, temp, moduleName)
		if err != nil {
			return Result{}, ErrOperational
		}
		status := "pass"
		if probe.After {
			status = "violation"
			diagnostics = append(diagnostics, Diagnostic{
				RuleID:      "PGP001",
				Severity:    "error",
				Module:      moduleName,
				Message:     "import re-enabled the GIL in a free-threaded interpreter",
				Remediation: "declare that the extension does not use the GIL only after verifying thread safety, or stop claiming free-threaded support",
			})
		}
		results = append(results, Module{
			Name:             moduleName,
			Discovery:        discovery,
			BeforeGILEnabled: probe.Before,
			AfterGILEnabled:  probe.After,
			WarningObserved:  probe.Warning,
			Status:           status,
			DurationMS:       duration,
		})
	}

	return Result{
		SchemaVersion: 1,
		ToolVersion:   "dev",
		Wheel:         filepath.Base(opts.Wheel),
		Python:        filepath.Base(opts.Python),
		Runtime:       runtimeInfo,
		Modules:       results,
		Diagnostics:   diagnostics,
		Summary: Summary{
			Checked:    len(results),
			Violations: len(diagnostics),
		},
	}, nil
}

func probeRuntime(python string, timeout time.Duration) (Runtime, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.Command(python, "-I", "-c", runtimeProbeScript)
	cmd.Env = []string{"PYTHONNOUSERSITE=1", "PYTHONDONTWRITEBYTECODE=1", "LC_ALL=C.UTF-8"}
	stdout, err := runBoundedCommand(ctx, cmd)
	if err != nil {
		return Runtime{}, ErrOperational
	}
	var result Runtime
	dec := json.NewDecoder(strings.NewReader(string(stdout)))
	if err := dec.Decode(&result); err != nil || dec.Decode(&struct{}{}) != io.EOF {
		return Runtime{}, ErrOperational
	}
	if result.Implementation != "cpython" || !result.GILDisabled || result.Version == "" || result.SOABI == "" || result.ExtensionSuffix == "" || result.Platform == "" || result.Machine == "" {
		return Runtime{}, ErrOperational
	}
	return result, nil
}

func validateWheelTag(wheel string, runtimeInfo Runtime) error {
	base := filepath.Base(wheel)
	if !strings.HasSuffix(base, ".whl") {
		return fmt.Errorf("wheel filename has no .whl suffix")
	}
	parts := strings.Split(strings.TrimSuffix(base, ".whl"), "-")
	if len(parts) < 5 {
		return fmt.Errorf("wheel filename has no complete compatibility tag")
	}
	pythonTags := strings.Split(parts[len(parts)-3], ".")
	abiTags := strings.Split(parts[len(parts)-2], ".")
	platformTags := strings.Split(parts[len(parts)-1], ".")
	versionDigits := strings.ReplaceAll(runtimeInfo.Version, ".", "")
	if !contains(pythonTags, "cp"+versionDigits) || !contains(abiTags, "cp"+versionDigits+"t") {
		return fmt.Errorf("wheel Python or ABI tag is incompatible with target")
	}
	for _, platformTag := range platformTags {
		if compatiblePlatformTag(platformTag, runtimeInfo) {
			return nil
		}
	}
	return fmt.Errorf("wheel platform tag is incompatible with target")
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func compatiblePlatformTag(tag string, runtimeInfo Runtime) bool {
	normalize := func(value string) string {
		value = strings.ToLower(value)
		value = strings.NewReplacer("-", "_", ".", "_").Replace(value)
		return value
	}
	tag = normalize(tag)
	platform := normalize(runtimeInfo.Platform)
	machine := normalize(runtimeInfo.Machine)
	if tag == "any" {
		return false
	}
	if tag == platform {
		return true
	}
	if strings.HasPrefix(platform, "linux_") && strings.HasPrefix(tag, "linux_") {
		return strings.HasSuffix(tag, "_"+machine)
	}
	if strings.HasPrefix(platform, "linux_") && strings.HasSuffix(tag, "_"+machine) {
		if major, minor, ok := policyVersion(tag, "manylinux_"); ok {
			return strings.EqualFold(runtimeInfo.Libc, "glibc") && versionAtLeast(runtimeInfo.LibcVersion, major, minor)
		}
		if major, minor, ok := policyVersion(tag, "musllinux_"); ok {
			return strings.EqualFold(runtimeInfo.Libc, "musl") && versionAtLeast(runtimeInfo.LibcVersion, major, minor)
		}
	}
	if strings.HasPrefix(platform, "macosx_") && strings.HasPrefix(tag, "macosx_") {
		archCompatible := strings.HasSuffix(tag, "_"+machine) || ((machine == "x86_64" || machine == "arm64") && strings.HasSuffix(tag, "_universal2"))
		wheelMajor, wheelMinor, wheelOK := policyVersion(tag, "macosx_")
		runtimeMajor, runtimeMinor, runtimeOK := policyVersion(platform, "macosx_")
		return archCompatible && wheelOK && runtimeOK && (runtimeMajor > wheelMajor || (runtimeMajor == wheelMajor && runtimeMinor >= wheelMinor))
	}
	return false
}

func policyVersion(tag, prefix string) (int, int, bool) {
	if !strings.HasPrefix(tag, prefix) {
		return 0, 0, false
	}
	var major, minor int
	if _, err := fmt.Sscanf(strings.TrimPrefix(tag, prefix), "%d_%d", &major, &minor); err != nil {
		return 0, 0, false
	}
	return major, minor, true
}

func versionAtLeast(version string, requiredMajor, requiredMinor int) bool {
	var major, minor int
	if _, err := fmt.Sscanf(version, "%d.%d", &major, &minor); err != nil {
		return false
	}
	return major > requiredMajor || (major == requiredMajor && minor >= requiredMinor)
}

func runProbe(parent context.Context, opts Options, root, moduleName string) (probeResult, int64, error) {
	ctx, cancel := context.WithTimeout(parent, opts.Timeout)
	defer cancel()
	started := time.Now()
	cmd := exec.Command(opts.Python, "-I", "-c", probeScript, root, moduleName)
	cmd.Env = []string{"PYTHONNOUSERSITE=1", "PYTHONDONTWRITEBYTECODE=1", "LC_ALL=C.UTF-8"}
	stdout, err := runBoundedCommand(ctx, cmd)
	duration := time.Since(started).Milliseconds()
	if err != nil {
		return probeResult{}, 0, ErrOperational
	}
	var probe probeResult
	dec := json.NewDecoder(strings.NewReader(string(stdout)))
	if err := dec.Decode(&probe); err != nil || dec.Decode(&struct{}{}) != io.EOF || probe.Before {
		return probeResult{}, 0, ErrOperational
	}
	return probe, duration, nil
}

var modulePart = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

func validateExplicitModules(modules []string) error {
	seen := make(map[string]struct{}, len(modules))
	for _, module := range modules {
		if !validModuleName(module) {
			return fmt.Errorf("invalid module name")
		}
		if _, exists := seen[module]; exists {
			return fmt.Errorf("duplicate module name")
		}
		seen[module] = struct{}{}
	}
	return nil
}

func validModuleName(module string) bool {
	parts := strings.Split(module, ".")
	if len(parts) == 0 {
		return false
	}
	for _, part := range parts {
		if !modulePart.MatchString(part) {
			return false
		}
	}
	return true
}

func discoverModules(wheel string) ([]string, error) {
	r, err := zip.OpenReader(wheel)
	if err != nil {
		return nil, err
	}
	defer r.Close()
	modules := make(map[string]struct{})
	for _, file := range r.File {
		name := filepath.ToSlash(file.Name)
		if file.FileInfo().IsDir() {
			continue
		}
		parts := strings.Split(name, "/")
		ignored := false
		for _, part := range parts[:len(parts)-1] {
			if strings.HasSuffix(part, ".dist-info") || strings.HasSuffix(part, ".egg-info") || strings.HasSuffix(part, ".libs") || strings.HasSuffix(part, ".dylibs") {
				ignored = true
				break
			}
			if strings.HasSuffix(part, ".data") {
				if isNativeFilename(parts[len(parts)-1]) {
					return nil, fmt.Errorf("native module in unsupported .data layout")
				}
				ignored = true
				break
			}
		}
		if ignored || !isNativeFilename(parts[len(parts)-1]) {
			continue
		}
		base := nativeBase(parts[len(parts)-1])
		if base == "" {
			return nil, fmt.Errorf("ambiguous native module filename")
		}
		parts[len(parts)-1] = base
		module := strings.Join(parts, ".")
		if !validModuleName(module) {
			return nil, fmt.Errorf("unsupported module path")
		}
		if _, exists := modules[module]; exists {
			return nil, fmt.Errorf("ambiguous duplicate module")
		}
		modules[module] = struct{}{}
	}
	result := make([]string, 0, len(modules))
	for module := range modules {
		result = append(result, module)
	}
	sort.Strings(result)
	if len(result) == 0 || len(result) > maxModules {
		return nil, fmt.Errorf("invalid discovered module count")
	}
	return result, nil
}

func isNativeFilename(name string) bool {
	return strings.HasSuffix(name, ".so") || strings.HasSuffix(strings.ToLower(name), ".pyd")
}

func nativeBase(name string) string {
	lower := strings.ToLower(name)
	if strings.HasSuffix(lower, ".pyd") {
		name = name[:len(name)-4]
	} else if strings.HasSuffix(name, ".so") {
		name = name[:len(name)-3]
	} else {
		return ""
	}
	for _, marker := range []string{".cpython-", ".abi3"} {
		if index := strings.Index(name, marker); index >= 0 {
			name = name[:index]
		}
	}
	if strings.Contains(name, ".") {
		return ""
	}
	return name
}

func extractWheel(wheel, target string) error {
	r, err := zip.OpenReader(wheel)
	if err != nil {
		return err
	}
	defer r.Close()
	if len(r.File) == 0 || len(r.File) > maxArchiveEntries {
		return fmt.Errorf("invalid archive entry count")
	}
	var total uint64
	seen := make(map[string]struct{}, len(r.File))
	for _, file := range r.File {
		name := filepath.ToSlash(file.Name)
		clean := filepath.ToSlash(filepath.Clean(name))
		if name == "" || strings.HasPrefix(name, "/") || clean == ".." || strings.HasPrefix(clean, "../") || clean != strings.TrimSuffix(name, "/") {
			return fmt.Errorf("unsafe archive path")
		}
		if _, ok := seen[clean]; ok {
			return fmt.Errorf("duplicate archive path")
		}
		seen[clean] = struct{}{}
		if file.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("symlink entries are not supported")
		}
		total, err = addExpandedSize(total, file.UncompressedSize64)
		if err != nil {
			return err
		}
		destination := filepath.Join(target, filepath.FromSlash(clean))
		if !strings.HasPrefix(destination, target+string(os.PathSeparator)) {
			return fmt.Errorf("archive escapes target")
		}
		if file.FileInfo().IsDir() {
			if err := os.MkdirAll(destination, 0o755); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
			return err
		}
		source, err := file.Open()
		if err != nil {
			return err
		}
		output, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err != nil {
			source.Close()
			return err
		}
		_, copyErr := io.Copy(output, io.LimitReader(source, int64(file.UncompressedSize64)+1))
		closeErr := output.Close()
		sourceErr := source.Close()
		if copyErr != nil || closeErr != nil || sourceErr != nil {
			return fmt.Errorf("archive extraction failed")
		}
	}
	return nil
}

func addExpandedSize(total, entry uint64) (uint64, error) {
	if entry > maxExtractedBytes || total > maxExtractedBytes-entry {
		return 0, fmt.Errorf("archive exceeds extraction limit")
	}
	return total + entry, nil
}

const probeScript = `
import importlib
import json
import sys
import warnings

root, module = sys.argv[1], sys.argv[2]
if not hasattr(sys, "_is_gil_enabled"):
    raise SystemExit(3)
sys.path.insert(0, root)
before = sys._is_gil_enabled()
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter("always")
    importlib.import_module(module)
after = sys._is_gil_enabled()
print(json.dumps({"before": before, "after": after, "warning": bool(caught)}, separators=(",", ":")))
`

const runtimeProbeScript = `
import json
import platform
import sys
import sysconfig

if not hasattr(sys, "_is_gil_enabled"):
    raise SystemExit(3)
version = f"{sys.version_info.major}.{sys.version_info.minor}"
libc_name, libc_version = platform.libc_ver()
print(json.dumps({
    "implementation": sys.implementation.name,
    "version": version,
    "gilDisabled": bool(sysconfig.get_config_var("Py_GIL_DISABLED")) and not sys._is_gil_enabled(),
    "soabi": sysconfig.get_config_var("SOABI") or "",
    "extensionSuffix": sysconfig.get_config_var("EXT_SUFFIX") or "",
    "platform": sysconfig.get_platform(),
    "machine": platform.machine(),
	"libc": libc_name,
	"libcVersion": libc_version,
}, separators=(",", ":")))
`
