// Package session persists chat history per task as a branching tree of nodes.
//
// Each message is a node linked to its parent; a session has a "head" pointing
// at the tip of the active branch. Appending adds children under the head, so
// pointing the head at an earlier node and continuing creates a divergent
// branch without destroying the old one. Summarization is non-destructive: a
// boundary node stores a summary and its ancestors are marked collapsed, so the
// context builder can replace a long prefix with one summary while the original
// nodes remain on disk.
//
// Old linear sessions ({id, turns:[...]}) are migrated to a node chain on load.
package session

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

// Turn is one message, used by callers appending to a session.
type Turn struct {
	Role    string    `json:"role"`
	Content string    `json:"content"`
	Time    time.Time `json:"time"`
}

// Node is one message in the conversation tree.
type Node struct {
	ID        string    `json:"id"`
	Parent    string    `json:"parent"`
	Role      string    `json:"role"`
	Content   string    `json:"content"`
	Summary   string    `json:"summary,omitempty"`
	Collapsed bool      `json:"collapsed,omitempty"`
	Time      time.Time `json:"time"`
}

// Session is a branching conversation identified by ID within a project.
type Session struct {
	ID      string           `json:"id"`
	Nodes   map[string]*Node `json:"nodes"`
	Head    string           `json:"head"`
	NextSeq int              `json:"next_seq"`

	// Turns is the legacy linear format, read only for migration.
	Turns []Turn `json:"turns,omitempty"`
}

// Path returns the nodes from root to head, in order.
func (s *Session) Path() []Node {
	return s.pathTo(s.Head)
}

// pathTo returns the nodes from root to nodeID, in order.
func (s *Session) pathTo(nodeID string) []Node {
	var rev []Node
	for id := nodeID; id != ""; {
		n := s.Nodes[id]
		if n == nil {
			break
		}
		rev = append(rev, *n)
		id = n.Parent
	}
	// reverse
	out := make([]Node, len(rev))
	for i, n := range rev {
		out[len(rev)-1-i] = n
	}
	return out
}

func (s *Session) newNode(parent, role, content string, t time.Time) *Node {
	s.NextSeq++
	n := &Node{
		ID:      fmt.Sprintf("n%d", s.NextSeq),
		Parent:  parent,
		Role:    role,
		Content: content,
		Time:    t,
	}
	s.Nodes[n.ID] = n
	return n
}

// Store serializes access to on-disk sessions for a single daemon process.
type Store struct {
	mu   sync.Mutex
	base string // if non-empty, sessions live under base/<project-key>/sessions
}

// New returns a Store. If base is non-empty, sessions for a project are stored
// under base/<project-key>/sessions (keeping them out of the user's repo);
// otherwise they live in each project's own .ami/sessions directory.
func New(base string) *Store { return &Store{base: base} }

var safeID = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

func sanitize(id string) string {
	id = strings.TrimSpace(id)
	if id == "" {
		id = "default"
	}
	return safeID.ReplaceAllString(id, "-")
}

// projectKey is a stable, filesystem-safe id for a project root: its basename
// plus a short hash of the full path (to avoid collisions between same-named
// projects in different locations).
func projectKey(root string) string {
	sum := sha256.Sum256([]byte(root))
	base := safeID.ReplaceAllString(filepath.Base(root), "-")
	if base == "" || base == "-" || base == "." {
		base = "project"
	}
	return base + "-" + hex.EncodeToString(sum[:])[:12]
}

func (s *Store) dir(root string) string {
	if s.base != "" {
		return filepath.Join(s.base, projectKey(root), "sessions")
	}
	return filepath.Join(root, ".ami", "sessions")
}

func (s *Store) path(root, id string) string {
	return filepath.Join(s.dir(root), sanitize(id)+".json")
}

// Load reads the session with id from the project at root, returning an empty
// (but valid) session if none exists yet, and migrating the legacy format.
func (s *Store) Load(root, id string) (*Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.load(root, id)
}

func (s *Store) load(root, id string) (*Session, error) {
	data, err := os.ReadFile(s.path(root, id))
	if os.IsNotExist(err) {
		return &Session{ID: sanitize(id), Nodes: map[string]*Node{}}, nil
	}
	if err != nil {
		return nil, err
	}
	var sess Session
	if err := json.Unmarshal(data, &sess); err != nil {
		return nil, fmt.Errorf("corrupt session %s: %w", id, err)
	}
	if sess.ID == "" {
		sess.ID = sanitize(id)
	}
	if sess.Nodes == nil {
		sess.Nodes = map[string]*Node{}
	}
	migrateLegacy(&sess)
	return &sess, nil
}

// migrateLegacy converts a linear Turns list into a node chain.
func migrateLegacy(s *Session) {
	if len(s.Nodes) > 0 || len(s.Turns) == 0 {
		s.Turns = nil
		return
	}
	parent := ""
	for _, t := range s.Turns {
		n := s.newNode(parent, t.Role, t.Content, t.Time)
		parent = n.ID
	}
	s.Head = parent
	s.Turns = nil
}

func (s *Store) save(root string, sess *Session) error {
	p := s.path(root, sess.ID)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return err
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

// Append adds turns as nodes under the current head, advancing the head, and
// persists the session.
func (s *Store) Append(root, id string, turns ...Turn) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	sess, err := s.load(root, id)
	if err != nil {
		return err
	}
	for _, t := range turns {
		n := sess.newNode(sess.Head, t.Role, t.Content, t.Time)
		sess.Head = n.ID
	}
	return s.save(root, sess)
}

// Branch points the head at nodeID so subsequent appends form a new branch.
func (s *Store) Branch(root, id, nodeID string) (*Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	sess, err := s.load(root, id)
	if err != nil {
		return nil, err
	}
	if sess.Nodes[nodeID] == nil {
		return nil, fmt.Errorf("node %q not found", nodeID)
	}
	sess.Head = nodeID
	if err := s.save(root, sess); err != nil {
		return nil, err
	}
	return sess, nil
}

// PathTo returns the nodes from root to nodeID (for building a summary prompt).
func (s *Store) PathTo(root, id, nodeID string) ([]Node, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, err := s.load(root, id)
	if err != nil {
		return nil, err
	}
	if sess.Nodes[nodeID] == nil {
		return nil, fmt.Errorf("node %q not found", nodeID)
	}
	return sess.pathTo(nodeID), nil
}

// ApplySummary stores summary on the boundary node and marks it and all its
// ancestors collapsed, so the context builder emits one summary in their place.
// Originals are retained.
func (s *Store) ApplySummary(root, id, boundaryID, summary string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	sess, err := s.load(root, id)
	if err != nil {
		return err
	}
	boundary := sess.Nodes[boundaryID]
	if boundary == nil {
		return fmt.Errorf("node %q not found", boundaryID)
	}
	for id := boundaryID; id != ""; {
		n := sess.Nodes[id]
		if n == nil {
			break
		}
		n.Collapsed = true
		n.Summary = "" // only the boundary carries the summary
		id = n.Parent
	}
	boundary.Summary = summary
	return s.save(root, sess)
}
