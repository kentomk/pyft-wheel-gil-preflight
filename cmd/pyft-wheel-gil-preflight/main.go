package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/kentomk/pyft-wheel-gil-preflight/internal/checker"
)

var version = "dev"

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) == 1 && args[0] == "version" {
		fmt.Printf("pyft-wheel-gil-preflight %s\n", version)
		return 0
	}
	if len(args) == 0 || args[0] != "check" {
		fmt.Fprintln(os.Stderr, "usage: pyft-wheel-gil-preflight check --wheel PATH --python PATH [--module NAME ...] [--format text|json] [--timeout 10s]")
		return 2
	}

	fs := flag.NewFlagSet("check", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	wheel := fs.String("wheel", "", "wheel artifact to inspect")
	python := fs.String("python", "", "free-threaded CPython executable")
	var modules stringList
	fs.Var(&modules, "module", "native module to import; repeat to override automatic discovery")
	format := fs.String("format", "text", "output format: text or json")
	timeout := fs.Duration("timeout", 10*time.Second, "module import timeout")
	if err := fs.Parse(args[1:]); err != nil || fs.NArg() != 0 {
		return 2
	}
	if *wheel == "" || *python == "" || (*format != "text" && *format != "json") || *timeout <= 0 || *timeout > time.Minute {
		fmt.Fprintln(os.Stderr, "invalid arguments: --wheel and --python are required; timeout must be 1ns..60s")
		return 2
	}

	result, err := checker.Check(checker.Options{
		Wheel:   *wheel,
		Python:  *python,
		Modules: modules,
		Timeout: *timeout,
	})
	if err != nil {
		result = checker.OperationalResult(filepath.Base(*wheel), filepath.Base(*python), strings.Join(modules, ","))
		_ = writeResult(os.Stdout, *format, result, true)
		if !errors.Is(err, checker.ErrOperational) {
			fmt.Fprintln(os.Stderr, "inspection failed")
		}
		return resultExitCode(result, true)
	}

	if err := writeResult(os.Stdout, *format, result, false); err != nil {
		return 2
	}
	return resultExitCode(result, false)
}

func resultExitCode(result checker.Result, operational bool) int {
	if operational || result.Summary.Errors > 0 {
		return 2
	}
	if result.Summary.Violations > 0 {
		return 1
	}
	return 0
}

func writeResult(w io.Writer, format string, result checker.Result, operational bool) error {
	if format == "json" {
		return json.NewEncoder(w).Encode(result)
	}
	if operational {
		_, err := fmt.Fprintln(w, "ERROR: inspection could not complete safely")
		return err
	}
	for _, module := range result.Modules {
		if module.Status == "violation" {
			if _, err := fmt.Fprintf(w, "PGP001 %s: import re-enabled the GIL\n", module.Name); err != nil {
				return err
			}
		} else if _, err := fmt.Fprintf(w, "PASS %s: GIL remained disabled after import\n", module.Name); err != nil {
			return err
		}
	}
	return nil
}

type stringList []string

func (s *stringList) String() string { return strings.Join(*s, ",") }

func (s *stringList) Set(value string) error {
	if strings.TrimSpace(value) == "" {
		return errors.New("module name cannot be empty")
	}
	*s = append(*s, value)
	return nil
}
