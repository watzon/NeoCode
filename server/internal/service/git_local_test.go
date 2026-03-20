package service

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/watzon/neocode/server/internal/core"
)

func TestLocalGitProviderLifecycle(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	provider := LocalGitProvider{}
	workspace := core.Workspace{ID: "ws1", LocalPathHint: root}
	if err := provider.Initialize(ctx, workspace); err != nil {
		t.Fatalf("initialize: %v", err)
	}
	branches, current, err := func() ([]string, string, error) {
		b, err := provider.Branches(ctx, workspace)
		if err != nil {
			return nil, "", err
		}
		c, err := provider.CurrentBranch(ctx, workspace)
		return b, c, err
	}()
	if err != nil || current == "" {
		t.Fatalf("unexpected branches/current: %v %v %q", branches, err, current)
	}
	if err := os.WriteFile(filepath.Join(root, "hello.txt"), []byte("hello"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}
	status, err := provider.Status(ctx, workspace)
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	if !status.HasChanges {
		t.Fatalf("expected changes: %#v", status)
	}
	if err := provider.CreateBranch(ctx, workspace, "feature/test"); err != nil {
		t.Fatalf("create branch: %v", err)
	}
}
