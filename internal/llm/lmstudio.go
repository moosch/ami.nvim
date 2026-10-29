// Package llm is a thin client for an OpenAI-compatible chat endpoint
// (LM Studio). It streams assistant tokens and respects context cancellation so
// an in-flight request can be aborted when the editor client disconnects.
package llm

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Role constants for chat messages.
const (
	RoleSystem    = "system"
	RoleUser      = "user"
	RoleAssistant = "assistant"
)

// Message is a single chat message.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// Client talks to an OpenAI-compatible chat completions endpoint.
type Client struct {
	baseURL string
	http    *http.Client
}

// New returns a Client for the given base URL (e.g.
// "http://localhost:1234/v1"). The HTTP client has no overall timeout
// because responses stream and the first request may trigger a slow model load;
// cancellation is driven by the request context instead.
func New(baseURL string) *Client {
	return &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		http: &http.Client{
			Transport: &http.Transport{
				// Allow a long cold-start model load, but don't hang forever.
				ResponseHeaderTimeout: 5 * time.Minute,
			},
		},
	}
}

// ListModels returns the ids of models the server currently exposes.
func (c *Client) ListModels(ctx context.Context) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/models", nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("lmstudio models request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("lmstudio returned %s for /models", resp.Status)
	}
	var out struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(out.Data))
	for _, m := range out.Data {
		ids = append(ids, m.ID)
	}
	return ids, nil
}

type chatCompletionRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
	Stream   bool      `json:"stream"`
}

// streamChunk is the subset of the streamed response we care about.
type streamChunk struct {
	Choices []struct {
		Delta struct {
			Content string `json:"content"`
		} `json:"delta"`
	} `json:"choices"`
}

// StreamChat sends messages to the model and invokes onToken for each content
// delta as it arrives. It returns when the stream completes, the context is
// cancelled, or an error occurs.
func (c *Client) StreamChat(ctx context.Context, model string, messages []Message, onToken func(string)) error {
	body, err := json.Marshal(chatCompletionRequest{
		Model:    model,
		Messages: messages,
		Stream:   true,
	})
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("lmstudio request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		snippet := make([]byte, 512)
		n, _ := resp.Body.Read(snippet)
		return fmt.Errorf("lmstudio returned %s: %s", resp.Status, strings.TrimSpace(string(snippet[:n])))
	}

	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		data, ok := strings.CutPrefix(line, "data: ")
		if !ok {
			continue
		}
		data = strings.TrimSpace(data)
		if data == "[DONE]" {
			break
		}
		var chunk streamChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue // skip malformed keep-alive/comment lines
		}
		for _, choice := range chunk.Choices {
			if choice.Delta.Content != "" {
				onToken(choice.Delta.Content)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		// A cancelled context surfaces here; report it as the context error.
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return fmt.Errorf("reading stream: %w", err)
	}
	return nil
}
