//go:build !linux && !darwin

package checker

import "os/exec"

func configureProcess(cmd *exec.Cmd) {}

func terminateProcessTree(cmd *exec.Cmd) {
	if cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
}
