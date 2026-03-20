package service

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/watzon/neocode/server/internal/core"
)

type LocalFileProvider struct {
	SkippedDirectoryNames map[string]struct{}
	ResultLimit           int
}

func (p LocalFileProvider) Search(ctx context.Context, workspace core.Workspace, query string, limit int) ([]core.FileMatch, error) {
	files, err := p.index(ctx, workspace)
	if err != nil {
		return nil, err
	}
	query = strings.ToLower(strings.TrimSpace(query))
	out := make([]core.FileMatch, 0)
	for _, file := range files {
		if query == "" || strings.Contains(strings.ToLower(file.Path), query) || strings.Contains(strings.ToLower(file.Name), query) {
			out = append(out, file)
		}
	}
	if limit <= 0 {
		limit = p.defaultLimit()
	}
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

func (p LocalFileProvider) Read(_ context.Context, workspace core.Workspace, path string) (core.FileContent, error) {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return core.FileContent{}, err
	}
	fullPath := filepath.Join(projectPath, filepath.Clean(path))
	data, err := os.ReadFile(fullPath)
	if err != nil {
		return core.FileContent{}, err
	}
	return core.FileContent{Path: path, Content: string(data), Encoding: "utf-8"}, nil
}

func (p LocalFileProvider) ResolveReferences(ctx context.Context, workspace core.Workspace, text string) ([]core.ResolvedFileReference, error) {
	files, err := p.index(ctx, workspace)
	if err != nil {
		return nil, err
	}
	byLower := make(map[string]core.FileMatch, len(files))
	for _, file := range files {
		byLower[strings.ToLower(file.Path)] = file
	}
	words := strings.Fields(text)
	out := make([]core.ResolvedFileReference, 0)
	searchOffset := 0
	for _, word := range words {
		if !strings.HasPrefix(word, "@") {
			searchOffset += len(word) + 1
			continue
		}
		ref := strings.TrimPrefix(word, "@")
		ref = strings.Trim(ref, ",.;:!?()[]{}\"'")
		match, ok := byLower[strings.ToLower(ref)]
		if !ok {
			searchOffset += len(word) + 1
			continue
		}
		content, _ := p.Read(ctx, workspace, match.Path)
		start := strings.Index(text[searchOffset:], word)
		if start >= 0 {
			start += searchOffset
		} else {
			start = searchOffset
		}
		end := start + len(word)
		out = append(out, core.ResolvedFileReference{Path: match.Path, Source: word, Start: start, End: end, Content: content.Content})
		searchOffset = end
	}
	return out, nil
}

func (p LocalFileProvider) index(ctx context.Context, workspace core.Workspace) ([]core.FileMatch, error) {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return nil, err
	}
	skipped := p.skippedDirectories()
	files := make([]core.FileMatch, 0)
	err = filepath.WalkDir(projectPath, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		if d.IsDir() {
			if _, skip := skipped[d.Name()]; skip {
				return filepath.SkipDir
			}
			return nil
		}
		rel, err := filepath.Rel(projectPath, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		dir := filepath.ToSlash(filepath.Dir(rel))
		if dir == "." {
			dir = ""
		}
		files = append(files, core.FileMatch{Path: rel, Name: filepath.Base(rel), Directory: dir})
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Path < files[j].Path })
	return files, nil
}

func (p LocalFileProvider) skippedDirectories() map[string]struct{} {
	if len(p.SkippedDirectoryNames) > 0 {
		return p.SkippedDirectoryNames
	}
	return map[string]struct{}{".git": {}, "node_modules": {}, "DerivedData": {}, ".build": {}, ".swiftpm": {}, "build": {}}
}

func (p LocalFileProvider) defaultLimit() int {
	if p.ResultLimit > 0 {
		return p.ResultLimit
	}
	return 40
}
