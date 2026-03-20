package runtime

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/opencode"
)

type Process interface {
	Start() error
	Wait() error
	Kill() error
	StdoutPipe() (io.ReadCloser, error)
	StderrPipe() (io.ReadCloser, error)
}

type ProcessFactory interface {
	New(ctx context.Context, name string, args []string, dir string, env []string) (Process, error)
}

type HealthClient interface {
	Health(ctx context.Context, baseURL, username, password string) (bool, string, error)
}

type Manager struct {
	mu          sync.Mutex
	entries     map[string]*entry
	processes   ProcessFactory
	httpClient  *http.Client
	health      HealthClient
	executable  string
	hostname    string
	username    string
	passwordLen int
	eventSink   func(core.ServerEvent)
}

type entry struct {
	workspaceID string
	baseURL     string
	username    string
	password    string
	version     string
	process     Process
	lastOutput  string
	startedAt   time.Time
	connected   bool
	client      *opencode.Client
	stopStream  context.CancelFunc
}

func NewManager(executable string, eventSink func(core.ServerEvent)) *Manager {
	client := &http.Client{Timeout: 30 * time.Second}
	return &Manager{
		entries:     map[string]*entry{},
		processes:   execFactory{},
		httpClient:  client,
		health:      healthAdapter{http: client},
		executable:  executable,
		hostname:    "127.0.0.1",
		username:    "opencode",
		passwordLen: 24,
		eventSink:   eventSink,
	}
}

func (m *Manager) SetProcessFactory(factory ProcessFactory) { m.processes = factory }
func (m *Manager) SetHealthClient(client HealthClient)      { m.health = client }
func (m *Manager) SetHTTPClient(client *http.Client)        { m.httpClient = client }

func (m *Manager) Ensure(ctx context.Context, workspace core.Workspace) (*opencode.Client, error) {
	path := strings.TrimSpace(workspace.LocalPathHint)
	if path == "" {
		return nil, errors.New("workspace local path is required for embedded runtime")
	}

	m.mu.Lock()
	if existing := m.entries[workspace.ID]; existing != nil && existing.connected {
		client := existing.client
		m.mu.Unlock()
		return client, nil
	}
	m.mu.Unlock()

	password := randomString(m.passwordLen)
	proc, err := m.processes.New(ctx, m.executable, []string{"serve", "--hostname", m.hostname, "--port", "0"}, path, []string{
		"OPENCODE_SERVER_USERNAME=" + m.username,
		"OPENCODE_SERVER_PASSWORD=" + password,
	})
	if err != nil {
		return nil, err
	}
	stdout, err := proc.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := proc.StderrPipe()
	if err != nil {
		return nil, err
	}
	if err := proc.Start(); err != nil {
		return nil, err
	}

	baseURL, output, err := detectBaseURL(ctx, io.MultiReader(stdout, stderr))
	if err != nil {
		_ = proc.Kill()
		return nil, err
	}
	healthCtx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	healthy, version, err := m.waitForHealth(healthCtx, baseURL, m.username, password)
	if err != nil || !healthy {
		_ = proc.Kill()
		if err == nil {
			err = errors.New("opencode runtime did not become healthy")
		}
		return nil, fmt.Errorf("runtime health failed: %w", err)
	}

	client := opencode.NewClient(baseURL, m.username, password, m.httpClient)
	entry := &entry{workspaceID: workspace.ID, baseURL: baseURL, username: m.username, password: password, version: version, process: proc, lastOutput: output, startedAt: time.Now().UTC(), connected: true, client: client}
	m.mu.Lock()
	m.entries[workspace.ID] = entry
	m.mu.Unlock()
	m.startEventBridge(workspace, entry)
	return client, nil
}

func (m *Manager) Stop(workspaceID string) error {
	m.mu.Lock()
	entry := m.entries[workspaceID]
	delete(m.entries, workspaceID)
	m.mu.Unlock()
	if entry == nil {
		return nil
	}
	if entry.stopStream != nil {
		entry.stopStream()
	}
	if entry.process != nil {
		return entry.process.Kill()
	}
	return nil
}

func (m *Manager) RawEventStream(ctx context.Context, workspace core.Workspace) (*http.Response, error) {
	client, err := m.Ensure(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.RawEventStream(ctx)
}

func (m *Manager) waitForHealth(ctx context.Context, baseURL, username, password string) (bool, string, error) {
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		healthy, version, err := m.health.Health(ctx, baseURL, username, password)
		if err == nil && healthy {
			return true, version, nil
		}
		select {
		case <-ctx.Done():
			if err != nil {
				return false, "", err
			}
			return false, "", ctx.Err()
		case <-ticker.C:
		}
	}
}

func (m *Manager) startEventBridge(workspace core.Workspace, entry *entry) {
	if m.eventSink == nil {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	entry.stopStream = cancel
	go func() {
		events, errs, err := entry.client.StreamEvents(ctx)
		if err != nil {
			m.eventSink(core.ServerEvent{ID: "bridge_error", WorkspaceID: workspace.ID, Type: "runtime.stream.error", Payload: map[string]any{"error": err.Error()}, CreatedAt: time.Now().UTC()})
			return
		}
		for {
			select {
			case <-ctx.Done():
				return
			case err, ok := <-errs:
				if ok && err != nil {
					m.eventSink(core.ServerEvent{ID: "bridge_error", WorkspaceID: workspace.ID, Type: "runtime.stream.error", Payload: map[string]any{"error": err.Error()}, CreatedAt: time.Now().UTC()})
				}
				return
			case event, ok := <-events:
				if !ok {
					return
				}
				event.WorkspaceID = workspace.ID
				m.eventSink(event)
			}
		}
	}()
}

func detectBaseURL(ctx context.Context, reader io.Reader) (string, string, error) {
	pattern := regexp.MustCompile(`https?://[^\s"'<>]+|(?:127\.0\.0\.1|0\.0\.0\.0|localhost|\[::1\]|::1):\d+`)
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 16*1024), 1024*1024)
	var output strings.Builder
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return "", output.String(), ctx.Err()
		default:
		}
		line := scanner.Text()
		output.WriteString(line)
		output.WriteString("\n")
		candidate := pattern.FindString(line)
		if candidate == "" {
			continue
		}
		candidate = strings.TrimRight(candidate, "\"'`.,;:!?)]}")
		if !strings.Contains(candidate, "://") {
			candidate = "http://" + candidate
		}
		candidate = strings.ReplaceAll(candidate, "0.0.0.0", "127.0.0.1")
		candidate = strings.ReplaceAll(candidate, "::1", "127.0.0.1")
		return candidate, output.String(), nil
	}
	if err := scanner.Err(); err != nil {
		return "", output.String(), err
	}
	return "", output.String(), errors.New("runtime did not report a listening address")
}

type execFactory struct{}

func (execFactory) New(ctx context.Context, name string, args []string, dir string, env []string) (Process, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), env...)
	return &execProcess{cmd: cmd}, nil
}

type execProcess struct{ cmd *exec.Cmd }

func (p *execProcess) Start() error { return p.cmd.Start() }
func (p *execProcess) Wait() error  { return p.cmd.Wait() }
func (p *execProcess) Kill() error {
	if p.cmd.Process != nil {
		return p.cmd.Process.Kill()
	}
	return nil
}
func (p *execProcess) StdoutPipe() (io.ReadCloser, error) { return p.cmd.StdoutPipe() }
func (p *execProcess) StderrPipe() (io.ReadCloser, error) { return p.cmd.StderrPipe() }

type healthAdapter struct{ http *http.Client }

func (h healthAdapter) Health(ctx context.Context, baseURL, username, password string) (bool, string, error) {
	client := opencode.NewClient(baseURL, username, password, h.http)
	return client.Health(ctx)
}

func randomString(length int) string {
	const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	buf := make([]byte, length)
	for i := range buf {
		buf[i] = alphabet[rand.Intn(len(alphabet))]
	}
	return string(buf)
}
