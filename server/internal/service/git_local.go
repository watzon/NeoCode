package service

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os/exec"
	"strconv"
	"strings"

	"github.com/watzon/neocode/server/internal/core"
)

type LocalGitProvider struct{}

func (LocalGitProvider) Status(ctx context.Context, workspace core.Workspace) (core.GitStatus, error) {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return core.GitStatus{}, err
	}
	if !isGitRepo(ctx, projectPath) {
		return core.GitStatus{}, nil
	}
	statusOutput, err := runGit(ctx, projectPath, "status", "--porcelain=v1", "--branch")
	if err != nil {
		return core.GitStatus{}, err
	}
	branch, _ := LocalGitProvider{}.CurrentBranch(ctx, workspace)
	changes := parseChangedFiles(statusOutput)
	remotes, _ := runGit(ctx, projectPath, "remote")
	return core.GitStatus{
		Branch:     branch,
		AheadCount: parseAheadCount(statusOutput),
		HasRemote:  strings.TrimSpace(remotes) != "",
		HasChanges: len(changes) > 0,
		Changes:    changes,
	}, nil

}

func (LocalGitProvider) Diff(ctx context.Context, workspace core.Workspace) (core.GitDiff, error) {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return core.GitDiff{}, err
	}
	patch, err := runGit(ctx, projectPath, "diff", "--cached", "--patch", "--stat")
	if err != nil {
		patch, err = runGit(ctx, projectPath, "diff", "--patch", "--stat")
		if err != nil {
			return core.GitDiff{}, err
		}
	}
	statusOutput, _ := runGit(ctx, projectPath, "status", "--porcelain=v1", "--branch")
	changes := parseChangedFiles(statusOutput)
	return core.GitDiff{Patch: patch, FileCount: len(changes), Changes: changes}, nil
}

func (LocalGitProvider) Preview(ctx context.Context, workspace core.Workspace) (core.GitCommitPreview, error) {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return core.GitCommitPreview{}, err
	}
	statusOutput, err := runGit(ctx, projectPath, "status", "--porcelain=v1", "--branch")
	if err != nil {
		return core.GitCommitPreview{}, err
	}
	branch, err := LocalGitProvider{}.CurrentBranch(ctx, workspace)
	if err != nil {
		return core.GitCommitPreview{}, err
	}
	stagedStatsOutput, _ := runGit(ctx, projectPath, "diff", "--cached", "--numstat")
	unstagedStatsOutput, _ := runGit(ctx, projectPath, "diff", "--numstat")
	totalStatsOutput, totalErr := pendingCommitStats(ctx, projectPath)
	if totalErr != nil {
		totalStatsOutput = unstagedStatsOutput
	}
	staged := parseNumstat(stagedStatsOutput)
	unstaged := parseNumstat(unstagedStatsOutput)
	total := parseNumstat(totalStatsOutput)
	return core.GitCommitPreview{
		Branch:            branch,
		ChangedFiles:      parseChangedFiles(statusOutput),
		StagedAdditions:   staged.additions,
		StagedDeletions:   staged.deletions,
		UnstagedAdditions: unstaged.additions,
		UnstagedDeletions: unstaged.deletions,
		TotalAdditions:    total.additions,
		TotalDeletions:    total.deletions,
	}, nil
}

func (LocalGitProvider) Commit(ctx context.Context, workspace core.Workspace, message string, includeUnstaged bool) error {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return err
	}
	trimmedMessage := strings.TrimSpace(message)
	log.Printf("git commit start workspace=%s path=%q includeUnstaged=%t messageLength=%d", workspace.ID, projectPath, includeUnstaged, len(trimmedMessage))
	if includeUnstaged {
		if _, err := runGit(ctx, projectPath, "add", "-A"); err != nil {
			log.Printf("git commit staging failed workspace=%s path=%q error=%v", workspace.ID, projectPath, err)
			return err
		}
	}
	_, err = runGit(ctx, projectPath, "commit", "-m", trimmedMessage)
	if err != nil {
		log.Printf("git commit failed workspace=%s path=%q error=%v", workspace.ID, projectPath, err)
		return err
	}
	log.Printf("git commit finished workspace=%s path=%q", workspace.ID, projectPath)
	return err
}

func (LocalGitProvider) Push(ctx context.Context, workspace core.Workspace) error {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return err
	}
	log.Printf("git push start workspace=%s path=%q", workspace.ID, projectPath)
	_, err = runGit(ctx, projectPath, "push")
	if err == nil {
		log.Printf("git push finished workspace=%s path=%q", workspace.ID, projectPath)
		return nil
	}
	branch, branchErr := LocalGitProvider{}.CurrentBranch(ctx, workspace)
	if branchErr != nil {
		log.Printf("git push failed workspace=%s path=%q error=%v", workspace.ID, projectPath, err)
		return err
	}
	_, upstreamErr := runGit(ctx, projectPath, "push", "-u", "origin", branch)
	if upstreamErr != nil {
		log.Printf("git push with upstream failed workspace=%s path=%q branch=%s error=%v", workspace.ID, projectPath, branch, upstreamErr)
		return err
	}
	log.Printf("git push finished workspace=%s path=%q branch=%s upstream=origin", workspace.ID, projectPath, branch)
	return nil
}

func (LocalGitProvider) Branches(ctx context.Context, workspace core.Workspace) ([]string, error) {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return nil, err
	}
	output, err := runGit(ctx, projectPath, "branch", "--format=%(refname:short)")
	if err != nil {
		return nil, err
	}
	lines := splitNonEmptyLines(output)
	return lines, nil
}

func (LocalGitProvider) CurrentBranch(ctx context.Context, workspace core.Workspace) (string, error) {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return "", err
	}
	output, err := runGit(ctx, projectPath, "branch", "--show-current")
	if err == nil && strings.TrimSpace(output) != "" {
		return strings.TrimSpace(output), nil
	}
	output, err = runGit(ctx, projectPath, "symbolic-ref", "--short", "HEAD")
	return strings.TrimSpace(output), err
}

func (LocalGitProvider) Initialize(ctx context.Context, workspace core.Workspace) error {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return err
	}
	log.Printf("git init start workspace=%s path=%q", workspace.ID, projectPath)
	_, err = runGit(ctx, projectPath, "init", "-b", "main")
	if err == nil {
		log.Printf("git init finished workspace=%s path=%q branch=main", workspace.ID, projectPath)
		return nil
	}
	_, err = runGit(ctx, projectPath, "init")
	if err != nil {
		log.Printf("git init failed workspace=%s path=%q error=%v", workspace.ID, projectPath, err)
		return err
	}
	_, _ = runGit(ctx, projectPath, "symbolic-ref", "HEAD", "refs/heads/main")
	log.Printf("git init finished workspace=%s path=%q branch=main fallback=true", workspace.ID, projectPath)
	return nil
}

func (LocalGitProvider) SwitchBranch(ctx context.Context, workspace core.Workspace, branch string) error {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return err
	}
	trimmedBranch := strings.TrimSpace(branch)
	log.Printf("git switch start workspace=%s path=%q branch=%s", workspace.ID, projectPath, trimmedBranch)
	_, err = runGit(ctx, projectPath, "switch", trimmedBranch)
	if err == nil {
		log.Printf("git switch finished workspace=%s path=%q branch=%s", workspace.ID, projectPath, trimmedBranch)
		return nil
	}
	_, err = runGit(ctx, projectPath, "checkout", trimmedBranch)
	if err != nil {
		log.Printf("git switch failed workspace=%s path=%q branch=%s error=%v", workspace.ID, projectPath, trimmedBranch, err)
		return err
	}
	log.Printf("git switch finished workspace=%s path=%q branch=%s fallback=checkout", workspace.ID, projectPath, trimmedBranch)
	return err
}

func (LocalGitProvider) CreateBranch(ctx context.Context, workspace core.Workspace, branch string) error {
	projectPath, err := workspacePath(workspace)
	if err != nil {
		return err
	}
	trimmedBranch := strings.TrimSpace(branch)
	log.Printf("git create-branch start workspace=%s path=%q branch=%s", workspace.ID, projectPath, trimmedBranch)
	_, err = runGit(ctx, projectPath, "switch", "-c", trimmedBranch)
	if err == nil {
		log.Printf("git create-branch finished workspace=%s path=%q branch=%s", workspace.ID, projectPath, trimmedBranch)
		return nil
	}
	_, err = runGit(ctx, projectPath, "checkout", "-b", trimmedBranch)
	if err != nil {
		log.Printf("git create-branch failed workspace=%s path=%q branch=%s error=%v", workspace.ID, projectPath, trimmedBranch, err)
		return err
	}
	log.Printf("git create-branch finished workspace=%s path=%q branch=%s fallback=checkout", workspace.ID, projectPath, trimmedBranch)
	return err
}

func runGit(ctx context.Context, projectPath string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "/usr/bin/env", append([]string{"git"}, args...)...)
	cmd.Dir = projectPath
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = strings.TrimSpace(stdout.String())
		}
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf("git %s: %s", strings.Join(args, " "), msg)
	}
	return stdout.String(), nil
}

func workspacePath(workspace core.Workspace) (string, error) {
	path := strings.TrimSpace(workspace.LocalPathHint)
	if path == "" {
		return "", fmt.Errorf("workspace %s has no local path", workspace.ID)
	}
	return path, nil
}

func isGitRepo(ctx context.Context, projectPath string) bool {
	output, err := runGit(ctx, projectPath, "rev-parse", "--is-inside-work-tree")
	return err == nil && strings.TrimSpace(output) == "true"
}

func splitNonEmptyLines(value string) []string {
	parts := strings.Split(value, "\n")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func parseAheadCount(output string) int {
	for _, line := range splitNonEmptyLines(output) {
		if !strings.HasPrefix(line, "## ") {
			continue
		}
		marker := "ahead "
		idx := strings.Index(line, marker)
		if idx < 0 {
			return 0
		}
		var value int
		_, _ = fmt.Sscanf(line[idx:], "ahead %d", &value)
		return value
	}
	return 0
}

func parseChangedFiles(output string) []core.GitFileChange {
	changes := make([]core.GitFileChange, 0)
	for _, line := range splitNonEmptyLines(output) {
		if strings.HasPrefix(line, "## ") || len(line) < 4 {
			continue
		}
		staged := line[0]
		unstaged := line[1]
		path := strings.TrimSpace(line[3:])
		if renamed := strings.Split(path, " -> "); len(renamed) > 1 {
			path = renamed[len(renamed)-1]
		}
		status := "changed"
		switch {
		case staged == '?' && unstaged == '?':
			status = "new"
		case staged == 'A' || unstaged == 'A':
			status = "added"
		case staged == 'D' || unstaged == 'D':
			status = "deleted"
		case staged == 'R' || unstaged == 'R':
			status = "renamed"
		case staged == 'M' || unstaged == 'M':
			status = "modified"
		}
		changes = append(changes, core.GitFileChange{Path: path, Status: status, IsTracked: status != "new", IsStaged: staged != ' ' && staged != '?', IsUnstaged: unstaged != ' ' || status == "new"})
	}
	return changes
}

func parseNumstat(output string) struct{ additions, deletions int } {
	result := struct{ additions, deletions int }{}
	for _, line := range splitNonEmptyLines(output) {
		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}
		if additions, err := strconv.Atoi(fields[0]); err == nil {
			result.additions += additions
		}
		if deletions, err := strconv.Atoi(fields[1]); err == nil {
			result.deletions += deletions
		}
	}
	return result
}

func pendingCommitStats(ctx context.Context, projectPath string) (string, error) {
	output, err := runGit(ctx, projectPath, "diff", "--cached", "--numstat")
	if err == nil && strings.TrimSpace(output) != "" {
		return output, nil
	}
	return runGit(ctx, projectPath, "diff", "--numstat")
}
