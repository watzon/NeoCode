package logging

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolvePathUsesEnvironmentOverride(t *testing.T) {
	customPath := filepath.Join(t.TempDir(), "custom.log")
	t.Setenv(logPathEnv, customPath)

	resolved, err := ResolvePathForTests()
	if err != nil {
		t.Fatalf("resolve path: %v", err)
	}
	if resolved != customPath {
		t.Fatalf("expected %q, got %q", customPath, resolved)
	}
}

func TestConfigureCreatesLogFile(t *testing.T) {
	customPath := filepath.Join(t.TempDir(), "logs", "neocoded.log")
	t.Setenv(logPathEnv, customPath)

	_, closer, err := Configure()
	if err != nil {
		t.Fatalf("configure logging: %v", err)
	}
	defer closer.Close()

	info, err := os.Stat(customPath)
	if err != nil {
		t.Fatalf("stat log file: %v", err)
	}
	if info.IsDir() {
		t.Fatalf("expected file, got directory")
	}
}
