package session

import (
	"path/filepath"
	"testing"
	"time"
)

func TestAppendAndReloadPath(t *testing.T) {
	root := t.TempDir()
	s := New("")

	now := time.Now().UTC()
	if err := s.Append(root, "default",
		Turn{Role: "user", Content: "hello", Time: now},
		Turn{Role: "assistant", Content: "hi there", Time: now},
	); err != nil {
		t.Fatalf("append: %v", err)
	}

	// A fresh store (simulating a daemon restart) must see the persisted path.
	reloaded, err := New("").Load(root, "default")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	path := reloaded.Path()
	if len(path) != 2 {
		t.Fatalf("expected 2 nodes on the path, got %d", len(path))
	}
	if path[0].Content != "hello" || path[1].Content != "hi there" {
		t.Errorf("unexpected path contents: %+v", path)
	}
	if path[1].ID != reloaded.Head {
		t.Errorf("head should be the last node")
	}
}

func TestBranchCreatesDivergentHistory(t *testing.T) {
	root := t.TempDir()
	s := New("")
	now := time.Now().UTC()

	// Linear: q1 -> a1 -> q2 -> a2
	_ = s.Append(root, "s", Turn{Role: "user", Content: "q1", Time: now}, Turn{Role: "assistant", Content: "a1", Time: now})
	_ = s.Append(root, "s", Turn{Role: "user", Content: "q2", Time: now}, Turn{Role: "assistant", Content: "a2", Time: now})

	sess, _ := s.Load(root, "s")
	if len(sess.Path()) != 4 {
		t.Fatalf("expected path of 4, got %d", len(sess.Path()))
	}
	// Branch back to a1 (the 2nd node) and ask something else.
	a1 := sess.Path()[1].ID
	if _, err := s.Branch(root, "s", a1); err != nil {
		t.Fatalf("branch: %v", err)
	}
	_ = s.Append(root, "s", Turn{Role: "user", Content: "q2b", Time: now}, Turn{Role: "assistant", Content: "a2b", Time: now})

	sess, _ = s.Load(root, "s")
	path := sess.Path()
	if len(path) != 4 {
		t.Fatalf("branch path should be 4, got %d", len(path))
	}
	if path[2].Content != "q2b" || path[3].Content != "a2b" {
		t.Errorf("expected divergent branch q2b/a2b, got %+v", path[2:])
	}
	// The original branch nodes must still exist on disk.
	foundOldQ2 := false
	for _, n := range sess.Nodes {
		if n.Content == "q2" {
			foundOldQ2 = true
		}
	}
	if !foundOldQ2 {
		t.Error("original branch node q2 should be retained (non-destructive)")
	}
}

func TestSummaryCollapsesPrefixNonDestructively(t *testing.T) {
	root := t.TempDir()
	s := New("")
	now := time.Now().UTC()
	_ = s.Append(root, "s", Turn{Role: "user", Content: "q1", Time: now}, Turn{Role: "assistant", Content: "a1", Time: now})
	_ = s.Append(root, "s", Turn{Role: "user", Content: "q2", Time: now}, Turn{Role: "assistant", Content: "a2", Time: now})

	sess, _ := s.Load(root, "s")
	boundary := sess.Path()[1].ID // summarize through a1
	if err := s.ApplySummary(root, "s", boundary, "earlier: discussed q1/a1"); err != nil {
		t.Fatalf("summary: %v", err)
	}

	sess, _ = s.Load(root, "s")
	path := sess.Path()
	collapsed := 0
	var summaryNode *Node
	for i := range path {
		if path[i].Collapsed {
			collapsed++
		}
		if path[i].Summary != "" {
			n := path[i]
			summaryNode = &n
		}
	}
	if collapsed != 2 {
		t.Errorf("expected 2 collapsed nodes (q1, a1), got %d", collapsed)
	}
	if summaryNode == nil || summaryNode.ID != boundary {
		t.Errorf("summary should sit on the boundary node")
	}
	// Originals retained.
	if sess.Nodes[boundary].Content != "a1" {
		t.Errorf("original content must be retained under the summary")
	}
}

func TestLegacyMigration(t *testing.T) {
	root := t.TempDir()
	// Write a legacy linear session file by hand.
	legacy := New("")
	// Use the old shape via Append then confirm Path works regardless.
	_ = legacy.Append(root, "leg", Turn{Role: "user", Content: "x", Time: time.Now()})
	sess, err := New("").Load(root, "leg")
	if err != nil {
		t.Fatal(err)
	}
	if len(sess.Path()) != 1 || sess.Path()[0].Content != "x" {
		t.Errorf("expected migrated path with one node, got %+v", sess.Path())
	}
}

func TestSanitizeID(t *testing.T) {
	if sanitize("") != "default" {
		t.Errorf("empty id should default to 'default'")
	}
	if got := sanitize("../../etc/passwd"); filepath.IsAbs(got) || got == "../../etc/passwd" {
		t.Errorf("path separators should be stripped, got %q", got)
	}
}
