package service

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/watzon/neocode/server/internal/core"
)

func TestLocalFileProviderSearchReadResolve(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "src"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "src", "main.go"), []byte("package main"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}
	provider := LocalFileProvider{}
	workspace := core.Workspace{ID: "ws1", LocalPathHint: root}
	matches, err := provider.Search(context.Background(), workspace, "main", 10)
	if err != nil || len(matches) != 1 {
		t.Fatalf("search: %v %#v", err, matches)
	}
	content, err := provider.Read(context.Background(), workspace, "src/main.go")
	if err != nil || content.Content != "package main" {
		t.Fatalf("read: %v %#v", err, content)
	}
	refs, err := provider.ResolveReferences(context.Background(), workspace, "look at @src/main.go")
	if err != nil || len(refs) != 1 {
		t.Fatalf("resolve refs: %v %#v", err, refs)
	}
}
