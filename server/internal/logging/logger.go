package logging

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

const logPathEnv = "NEOCODE_SERVER_LOG_PATH"

func Configure() (string, io.Closer, error) {
	path, err := resolvePath()
	if err != nil {
		return "", nil, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", nil, fmt.Errorf("create log directory: %w", err)
	}

	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return "", nil, fmt.Errorf("open log file: %w", err)
	}

	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.LUTC)
	log.SetOutput(io.MultiWriter(os.Stderr, file))
	return path, file, nil
}

func ResolvePathForTests() (string, error) {
	return resolvePath()
}

func resolvePath() (string, error) {
	if configured := strings.TrimSpace(os.Getenv(logPathEnv)); configured != "" {
		return configured, nil
	}

	home, err := os.UserHomeDir()
	if err == nil && strings.TrimSpace(home) != "" {
		return filepath.Join(home, "Library", "Logs", "NeoCode", "neocoded.log"), nil
	}

	cacheDir, cacheErr := os.UserCacheDir()
	if cacheErr == nil && strings.TrimSpace(cacheDir) != "" {
		return filepath.Join(cacheDir, "NeoCode", "neocoded.log"), nil
	}

	return "", fmt.Errorf("resolve log path: %w / %v", err, cacheErr)
}
