// Package context assembles the editor and project context sent to the model.
//
// Stage 1 scope: README.md + PLAN.md from the project root, the active buffer
// contents, and the current selection, trimmed to a token budget. LSP-driven
// dependency expansion is added in Stage 2.
package context

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Refs is what the editor sends to describe the current situation. The daemon
// reads project files itself from ProjectRoot; buffer contents come inline
// because an unsaved buffer may differ from disk.
type Refs struct {
	ProjectRoot   string `json:"project_root"`
	ActivePath    string `json:"active_path"`
	ActiveContent string `json:"active_content"`
	Selection     string `json:"selection"`
	Language      string `json:"language"`
	CursorLine    int    `json:"cursor_line"`
	// DepPaths are absolute paths to files the active code depends on, resolved
	// by the editor via LSP (definitions of nearby symbols). The daemon reads
	// and trims them; it does not resolve dependencies itself.
	DepPaths []string `json:"dep_paths"`
}

// approxTokens estimates tokens from characters (~4 chars/token). Good enough
// for budgeting without pulling in a tokenizer.
func approxTokens(s string) int { return len(s) / 4 }

// EstimateTokens exposes the token estimate for logging/budget reporting.
func EstimateTokens(s string) int { return approxTokens(s) }

// projectDocs returns the contents of README.md and PLAN.md if present at the
// project root.
func projectDocs(root string) []section {
	if root == "" {
		return nil
	}
	var out []section
	for _, name := range []string{"README.md", "PLAN.md"} {
		data, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			continue
		}
		out = append(out, section{title: name, body: string(data)})
	}
	return out
}

// depSections reads each dependency file, skipping the active file, duplicates,
// and anything unreadable.
func depSections(root string, paths []string, activePath string) []section {
	var out []section
	seen := map[string]bool{}
	for _, p := range paths {
		if p == "" || p == activePath || seen[p] {
			continue
		}
		seen[p] = true
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		title := p
		if root != "" {
			if rel, err := filepath.Rel(root, p); err == nil && !strings.HasPrefix(rel, "..") {
				title = rel
			}
		}
		out = append(out, section{title: "Dependency: " + title, body: string(data)})
	}
	return out
}

type section struct {
	title string
	body  string
}

// Assemble builds a single context string from refs, ordered by importance and
// trimmed so the total stays within budgetTokens. Order (most to least
// important): active selection, active buffer, LSP dependencies, README/PLAN.
func Assemble(refs Refs, budgetTokens int) string {
	var sections []section

	if sel := strings.TrimSpace(refs.Selection); sel != "" {
		sections = append(sections, section{
			title: fmt.Sprintf("Selection in %s (around line %d)", displayPath(refs), refs.CursorLine),
			body:  sel,
		})
	}
	if content := strings.TrimSpace(refs.ActiveContent); content != "" {
		sections = append(sections, section{
			title: fmt.Sprintf("Active file: %s", displayPath(refs)),
			body:  content,
		})
	}
	sections = append(sections, depSections(refs.ProjectRoot, refs.DepPaths, refs.ActivePath)...)
	sections = append(sections, projectDocs(refs.ProjectRoot)...)

	return render(sections, budgetTokens)
}

func displayPath(refs Refs) string {
	if refs.ActivePath == "" {
		return "(unsaved buffer)"
	}
	if refs.ProjectRoot != "" {
		if rel, err := filepath.Rel(refs.ProjectRoot, refs.ActivePath); err == nil && !strings.HasPrefix(rel, "..") {
			return rel
		}
	}
	return refs.ActivePath
}

// render concatenates sections into fenced blocks, trimming the last sections
// that would overflow the budget and noting the truncation.
func render(sections []section, budgetTokens int) string {
	var b strings.Builder
	used := 0
	for _, s := range sections {
		block := fmt.Sprintf("## %s\n\n```\n%s\n```\n\n", s.title, s.body)
		cost := approxTokens(block)
		if used+cost > budgetTokens && used > 0 {
			b.WriteString("_(further context omitted to stay within the token budget)_\n")
			break
		}
		// If a single section alone exceeds the budget, include a truncated head.
		if cost > budgetTokens {
			maxChars := budgetTokens * 4
			if maxChars < len(block) {
				block = block[:maxChars] + "\n…(truncated)…\n```\n\n"
			}
		}
		b.WriteString(block)
		used += cost
	}
	return strings.TrimSpace(b.String())
}
