package context

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAssembleOrdersSelectionFirst(t *testing.T) {
	out := Assemble(Refs{
		ActivePath:    "main.go",
		ActiveContent: "package main",
		Selection:     "fmt.Println(x)",
		CursorLine:    10,
	}, 8000)

	selIdx := strings.Index(out, "Selection")
	fileIdx := strings.Index(out, "Active file")
	if selIdx == -1 || fileIdx == -1 {
		t.Fatalf("expected both selection and active file sections, got:\n%s", out)
	}
	if selIdx > fileIdx {
		t.Errorf("selection should come before active file; sel=%d file=%d", selIdx, fileIdx)
	}
}

func TestAssembleIncludesProjectDocs(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("the readme"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "PLAN.md"), []byte("the plan"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := Assemble(Refs{ProjectRoot: dir}, 8000)
	if !strings.Contains(out, "the readme") || !strings.Contains(out, "the plan") {
		t.Errorf("expected README and PLAN contents in output:\n%s", out)
	}
}

func TestAssembleIncludesDepsAndSkipsActive(t *testing.T) {
	dir := t.TempDir()
	dep := filepath.Join(dir, "helper.go")
	active := filepath.Join(dir, "main.go")
	if err := os.WriteFile(dep, []byte("package p // helper body"), 0o644); err != nil {
		t.Fatal(err)
	}

	out := Assemble(Refs{
		ProjectRoot:   dir,
		ActivePath:    active,
		ActiveContent: "package p // main body",
		DepPaths:      []string{dep, active, "", dep}, // active + dupes must be ignored
	}, 8000)

	if !strings.Contains(out, "Dependency: helper.go") {
		t.Errorf("expected dependency section for helper.go:\n%s", out)
	}
	if !strings.Contains(out, "helper body") {
		t.Errorf("expected dependency file contents:\n%s", out)
	}
	if strings.Count(out, "Dependency:") != 1 {
		t.Errorf("active file and duplicates should not become dependency sections:\n%s", out)
	}
	// Active buffer must come before the dependency.
	if strings.Index(out, "Active file") > strings.Index(out, "Dependency:") {
		t.Errorf("active buffer should rank before dependencies:\n%s", out)
	}
}

func TestAssembleRespectsBudget(t *testing.T) {
	big := strings.Repeat("x", 100_000) // ~25k tokens
	out := Assemble(Refs{
		ActiveContent: big,
		Selection:     "small selection",
	}, 100) // tiny budget

	if approxTokens(out) > 400 {
		t.Errorf("output exceeded budget: ~%d tokens", approxTokens(out))
	}
	// The small, higher-priority selection should survive.
	if !strings.Contains(out, "small selection") {
		t.Errorf("expected high-priority selection to be kept:\n%s", out)
	}
}
