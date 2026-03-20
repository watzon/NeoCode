package runtime

import (
	"context"
	"io"
	"strings"
	"testing"

	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/opencode"
)

type fakeProcess struct {
	stdout  io.ReadCloser
	stderr  io.ReadCloser
	started bool
	killed  bool
}

func (p *fakeProcess) Start() error                       { p.started = true; return nil }
func (p *fakeProcess) Wait() error                        { return nil }
func (p *fakeProcess) Kill() error                        { p.killed = true; return nil }
func (p *fakeProcess) StdoutPipe() (io.ReadCloser, error) { return p.stdout, nil }
func (p *fakeProcess) StderrPipe() (io.ReadCloser, error) { return p.stderr, nil }

type fakeFactory struct{ proc Process }

func (f fakeFactory) New(context.Context, string, []string, string, []string) (Process, error) {
	return f.proc, nil
}

type fakeHealth struct{}

func (fakeHealth) Health(context.Context, string, string, string) (bool, string, error) {
	return true, "1.0.0", nil
}

func TestDetectBaseURL(t *testing.T) {
	url, output, err := detectBaseURL(context.Background(), strings.NewReader("server ready at http://127.0.0.1:1234\n"))
	if err != nil {
		t.Fatalf("detect base url: %v", err)
	}
	if url != "http://127.0.0.1:1234" {
		t.Fatalf("unexpected url: %s", url)
	}
	if !strings.Contains(output, "server ready") {
		t.Fatalf("unexpected output: %s", output)
	}
}

func TestManagerEnsure(t *testing.T) {
	manager := NewManager("opencode", nil)
	proc := &fakeProcess{stdout: io.NopCloser(strings.NewReader("ready http://127.0.0.1:3210\n")), stderr: io.NopCloser(strings.NewReader(""))}
	manager.SetProcessFactory(fakeFactory{proc: proc})
	manager.SetHealthClient(fakeHealth{})
	manager.SetHTTPClient(nil)
	client, err := manager.Ensure(context.Background(), core.Workspace{ID: "ws1", LocalPathHint: "/tmp/repo"})
	if err != nil {
		t.Fatalf("ensure: %v", err)
	}
	if client == nil || !proc.started {
		t.Fatal("expected client and started process")
	}
	if _, ok := any(client).(*opencode.Client); !ok {
		t.Fatal("expected opencode client")
	}
}
