// Package server exposes the amid HTTP API consumed by the Neovim plugin.
//
//	GET  /health  -> JSON status
//	POST /echo    -> SSE stream echoing the posted text (transport test)
//	POST /chat    -> SSE stream of advisor tokens for a chat turn
package server

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/moosch/ami.nvim/internal/config"
	amictx "github.com/moosch/ami.nvim/internal/context"
	"github.com/moosch/ami.nvim/internal/llm"
	"github.com/moosch/ami.nvim/internal/prompt"
	"github.com/moosch/ami.nvim/internal/session"
)

// Version is the daemon version, surfaced on /health so the plugin can detect a
// stale binary. Bump it on release.
const Version = "0.2.0"

// Server wires the daemon's dependencies to its HTTP handlers.
type Server struct {
	cfg      config.Config
	log      *slog.Logger
	llm      *llm.Client
	sessions *session.Store
}

// New returns a Server configured with cfg and log.
func New(cfg config.Config, log *slog.Logger) *Server {
	return &Server{
		cfg:      cfg,
		log:      log,
		llm:      llm.New(cfg.LMStudioBaseURL),
		sessions: session.New(cfg.DataDir),
	}
}

// Handler builds the HTTP routes for the daemon.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /models", s.handleModels)
	mux.HandleFunc("POST /echo", s.handleEcho)
	mux.HandleFunc("POST /chat", s.handleChat)
	mux.HandleFunc("POST /nudge", s.handleNudge)
	mux.HandleFunc("POST /tree", s.handleTree)
	mux.HandleFunc("POST /branch", s.handleBranch)
	mux.HandleFunc("POST /summarize", s.handleSummarize)
	return mux
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status":    "ok",
		"version":   Version,
		"model":     s.cfg.ChatModel,
		"lmstudio":  s.cfg.LMStudioBaseURL,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	})
}

type echoRequest struct {
	Text string `json:"text"`
}

// handleEcho streams the posted text back one rune at a time as SSE "token"
// events, ending with a "done" event. Kept from Stage 0 as a transport probe.
func (s *Server) handleEcho(w http.ResponseWriter, r *http.Request) {
	var req echoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	sse, err := NewSSEWriter(w)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	ctx := r.Context()
	for _, ch := range req.Text {
		select {
		case <-ctx.Done():
			return
		default:
		}
		if err := sse.Event("token", map[string]string{"content": string(ch)}); err != nil {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	_ = sse.Event("done", map[string]any{})
}

// handleModels proxies the LM Studio model list for the UI's model selector.
func (s *Server) handleModels(w http.ResponseWriter, r *http.Request) {
	ids, err := s.llm.ListModels(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeJSON(w, map[string]any{"models": ids, "default": s.cfg.ChatModel})
}

type chatRequest struct {
	SessionID string      `json:"session_id"`
	Message   string      `json:"message"`
	Model     string      `json:"model"`
	Context   amictx.Refs `json:"context"`
}

// handleChat runs one advisor turn: it loads the session, assembles context,
// streams the model's reply to the client, and persists the turn on success.
func (s *Server) handleChat(w http.ResponseWriter, r *http.Request) {
	var req chatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Message) == "" {
		http.Error(w, "empty message", http.StatusBadRequest)
		return
	}
	if req.SessionID == "" {
		req.SessionID = "default"
	}

	sse, err := NewSSEWriter(w)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	root := req.Context.ProjectRoot
	sess, err := s.sessions.Load(root, req.SessionID)
	if err != nil {
		s.log.Error("session load failed", "err", err)
		_ = sse.Event("error", map[string]string{"message": "could not load session: " + err.Error()})
		return
	}

	// Build the message list: advisor system prompt + fresh context, then the
	// prior turns, then the new user message.
	contextBlock := amictx.Assemble(req.Context, s.cfg.ContextTokenBudget)
	s.log.Info("context assembled",
		"session", req.SessionID,
		"chars", len(contextBlock),
		"approx_tokens", amictx.EstimateTokens(contextBlock),
		"budget", s.cfg.ContextTokenBudget,
		"dep_paths", len(req.Context.DepPaths),
	)
	messages := []llm.Message{{Role: llm.RoleSystem, Content: prompt.Build(contextBlock)}}
	messages = append(messages, pathMessages(sess.Path())...)
	messages = append(messages, llm.Message{Role: llm.RoleUser, Content: req.Message})

	model := req.Model
	if model == "" {
		model = s.cfg.ChatModel
	}
	s.log.Info("chat turn", "session", req.SessionID, "model", model)

	var reply strings.Builder
	err = s.llm.StreamChat(r.Context(), model, messages, func(tok string) {
		reply.WriteString(tok)
		_ = sse.Event("token", map[string]string{"content": tok})
	})
	if err != nil {
		s.log.Error("chat stream failed", "err", err)
		_ = sse.Event("error", map[string]string{"message": err.Error()})
		return
	}

	// Persist the turn only after a successful stream.
	now := time.Now().UTC()
	if perr := s.sessions.Append(root, req.SessionID,
		session.Turn{Role: llm.RoleUser, Content: req.Message, Time: now},
		session.Turn{Role: llm.RoleAssistant, Content: reply.String(), Time: now},
	); perr != nil {
		s.log.Error("session append failed", "err", perr)
	}

	_ = sse.Event("done", map[string]any{})
}

// handleNudge produces an unsolicited, proactive suggestion for the current
// context. It is NOT persisted to the session (it was never asked for), and an
// empty/NO_SUGGESTION reply means "stay silent".
func (s *Server) handleNudge(w http.ResponseWriter, r *http.Request) {
	var req chatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if req.SessionID == "" {
		req.SessionID = "default"
	}

	root := req.Context.ProjectRoot
	sess, err := s.sessions.Load(root, req.SessionID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	contextBlock := amictx.Assemble(req.Context, s.cfg.ContextTokenBudget)
	messages := []llm.Message{{Role: llm.RoleSystem, Content: prompt.BuildNudge(contextBlock)}}
	messages = append(messages, pathMessages(sess.Path())...)
	messages = append(messages, llm.Message{
		Role:    llm.RoleUser,
		Content: "(Proactively review the current context. Offer one brief, optional suggestion, or reply NO_SUGGESTION.)",
	})

	model := req.Model
	if model == "" {
		model = s.cfg.ChatModel
	}

	var reply strings.Builder
	if err := s.llm.StreamChat(r.Context(), model, messages, func(tok string) {
		reply.WriteString(tok)
	}); err != nil {
		s.log.Error("nudge stream failed", "err", err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}

	suggestion := strings.TrimSpace(reply.String())
	if suggestion == "NO_SUGGESTION" {
		suggestion = ""
	}
	writeJSON(w, map[string]any{"suggestion": suggestion})
}

// pathMessages converts a conversation path to LLM messages, replacing a
// collapsed, summarized prefix with a single summary message.
func pathMessages(nodes []session.Node) []llm.Message {
	var msgs []llm.Message
	for _, n := range nodes {
		if n.Collapsed {
			if n.Summary != "" {
				msgs = append(msgs, llm.Message{
					Role:    llm.RoleSystem,
					Content: "Summary of earlier conversation:\n" + n.Summary,
				})
			}
			continue
		}
		msgs = append(msgs, llm.Message{Role: n.Role, Content: n.Content})
	}
	return msgs
}

type treeRequest struct {
	SessionID   string `json:"session_id"`
	ProjectRoot string `json:"project_root"`
	NodeID      string `json:"node_id"`
	Model       string `json:"model"`
}

func decodeTreeRequest(w http.ResponseWriter, r *http.Request) (treeRequest, bool) {
	var req treeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return req, false
	}
	if req.SessionID == "" {
		req.SessionID = "default"
	}
	return req, true
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

// handleTree returns the conversation tree and active path for the UI to render.
func (s *Server) handleTree(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeTreeRequest(w, r)
	if !ok {
		return
	}
	sess, err := s.sessions.Load(req.ProjectRoot, req.SessionID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	nodes := make([]session.Node, 0, len(sess.Nodes))
	for _, n := range sess.Nodes {
		nodes = append(nodes, *n)
	}
	path := sess.Path()
	pathIDs := make([]string, len(path))
	for i, n := range path {
		pathIDs[i] = n.ID
	}
	writeJSON(w, map[string]any{
		"head":  sess.Head,
		"nodes": nodes,
		"path":  pathIDs,
	})
}

// handleBranch points the head at a node and returns the new active path.
func (s *Server) handleBranch(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeTreeRequest(w, r)
	if !ok {
		return
	}
	sess, err := s.sessions.Branch(req.ProjectRoot, req.SessionID, req.NodeID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, map[string]any{"head": sess.Head, "path": sess.Path()})
}

// handleSummarize asks the model to summarize the path up to a node, then marks
// that prefix collapsed so future turns send the summary in its place.
func (s *Server) handleSummarize(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeTreeRequest(w, r)
	if !ok {
		return
	}
	nodes, err := s.sessions.PathTo(req.ProjectRoot, req.SessionID, req.NodeID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var convo strings.Builder
	for _, n := range nodes {
		content := n.Content
		if n.Collapsed && n.Summary != "" {
			content = n.Summary
		}
		fmt.Fprintf(&convo, "%s: %s\n\n", n.Role, content)
	}

	messages := []llm.Message{
		{Role: llm.RoleSystem, Content: "You summarize a pair-programming conversation concisely, preserving decisions made, constraints, and open questions. Output a tight prose summary, no preamble."},
		{Role: llm.RoleUser, Content: "Summarize the conversation so far:\n\n" + convo.String()},
	}

	model := req.Model
	if model == "" {
		model = s.cfg.ChatModel
	}
	var summary strings.Builder
	if err := s.llm.StreamChat(r.Context(), model, messages, func(tok string) {
		summary.WriteString(tok)
	}); err != nil {
		s.log.Error("summarize stream failed", "err", err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}

	trimmed := strings.TrimSpace(summary.String())
	if err := s.sessions.ApplySummary(req.ProjectRoot, req.SessionID, req.NodeID, trimmed); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "summary": trimmed})
}
