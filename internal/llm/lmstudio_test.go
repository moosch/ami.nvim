package llm

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// mockLMStudio serves a canned SSE chat-completion stream in the OpenAI format.
func mockLMStudio(t *testing.T, deltas []string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat/completions" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "text/event-stream")
		flusher := w.(http.Flusher)
		for _, d := range deltas {
			fmt.Fprintf(w, "data: {\"choices\":[{\"delta\":{\"content\":%q}}]}\n\n", d)
			flusher.Flush()
		}
		fmt.Fprint(w, "data: [DONE]\n\n")
		flusher.Flush()
	}))
}

func TestStreamChatAssemblesTokens(t *testing.T) {
	srv := mockLMStudio(t, []string{"Hello", ", ", "world"})
	defer srv.Close()

	var got strings.Builder
	err := New(srv.URL).StreamChat(context.Background(), "test-model",
		[]Message{{Role: RoleUser, Content: "hi"}},
		func(tok string) { got.WriteString(tok) },
	)
	if err != nil {
		t.Fatalf("StreamChat: %v", err)
	}
	if got.String() != "Hello, world" {
		t.Errorf("got %q, want %q", got.String(), "Hello, world")
	}
}

func TestStreamChatSurfacesHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "model not found", http.StatusNotFound)
	}))
	defer srv.Close()

	err := New(srv.URL).StreamChat(context.Background(), "missing",
		[]Message{{Role: RoleUser, Content: "hi"}}, func(string) {})
	if err == nil {
		t.Fatal("expected an error for a 404 response")
	}
	if !strings.Contains(err.Error(), "model not found") {
		t.Errorf("error should include server message, got: %v", err)
	}
}

func TestStreamChatHonorsContextCancel(t *testing.T) {
	srv := mockLMStudio(t, []string{"a", "b", "c"})
	defer srv.Close()

	ctx, cancel := context.WithCancel(context.Background())
	err := New(srv.URL).StreamChat(ctx, "test-model",
		[]Message{{Role: RoleUser, Content: "hi"}},
		func(string) { cancel() }, // cancel on first token
	)
	// Either a clean finish or a context error is acceptable; a panic/other error is not.
	if err != nil && err != context.Canceled {
		t.Errorf("unexpected error: %v", err)
	}
}
