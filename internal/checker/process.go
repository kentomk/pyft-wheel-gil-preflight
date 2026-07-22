package checker

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"time"
)

const (
	maxChildStreamBytes = 16 << 10
	pipeCleanupGrace    = 500 * time.Millisecond
)

type streamResult struct {
	data     []byte
	exceeded bool
	err      error
	stream   int
}

type waitResult struct {
	state *os.ProcessState
	err   error
}

func runBoundedCommand(ctx context.Context, cmd *exec.Cmd) ([]byte, error) {
	configureProcess(cmd)
	stdoutReader, stdoutWriter, err := os.Pipe()
	if err != nil {
		return nil, ErrOperational
	}
	stderrReader, stderrWriter, err := os.Pipe()
	if err != nil {
		stdoutReader.Close()
		stdoutWriter.Close()
		return nil, ErrOperational
	}
	cmd.Stdout = stdoutWriter
	cmd.Stderr = stderrWriter
	if err := cmd.Start(); err != nil {
		stdoutReader.Close()
		stdoutWriter.Close()
		stderrReader.Close()
		stderrWriter.Close()
		return nil, ErrOperational
	}
	stdoutWriter.Close()
	stderrWriter.Close()

	streams := make(chan streamResult, 2)
	go readBoundedStream(stdoutReader, 1, streams)
	go readBoundedStream(stderrReader, 2, streams)
	waited := make(chan waitResult, 1)
	go func() {
		state, waitErr := cmd.Process.Wait()
		waited <- waitResult{state: state, err: waitErr}
	}()

	var stdout []byte
	var state *os.ProcessState
	var waitErr error
	streamCount := 0
	failed := false
	killed := false
	var cleanup <-chan time.Time
	for state == nil || streamCount < 2 {
		select {
		case result := <-streams:
			streamCount++
			if result.stream == 1 {
				stdout = result.data
			}
			if result.exceeded || (result.err != nil && !errors.Is(result.err, os.ErrClosed)) {
				failed = true
				if !killed {
					terminateProcessTree(cmd)
					killed = true
				}
			}
		case result := <-waited:
			state = result.state
			waitErr = result.err
			terminateProcessTree(cmd)
			killed = true
			cleanup = time.After(pipeCleanupGrace)
		case <-ctx.Done():
			failed = true
			if !killed {
				terminateProcessTree(cmd)
				killed = true
			}
		case <-cleanup:
			failed = true
			stdoutReader.Close()
			stderrReader.Close()
			cleanup = nil
		}
	}
	stdoutReader.Close()
	stderrReader.Close()
	if failed || waitErr != nil || state == nil || !state.Success() {
		return nil, ErrOperational
	}
	return stdout, nil
}

func readBoundedStream(reader *os.File, stream int, results chan<- streamResult) {
	data, err := io.ReadAll(io.LimitReader(reader, maxChildStreamBytes+1))
	exceeded := len(data) > maxChildStreamBytes
	if exceeded {
		data = data[:maxChildStreamBytes]
	}
	results <- streamResult{data: data, exceeded: exceeded, err: err, stream: stream}
}
