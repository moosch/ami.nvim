// Package config holds the amid daemon configuration, loaded from
// environment variables with sensible local-first defaults.
package config

import (
	"os"
	"strconv"
)

// Config is the daemon's runtime configuration.
type Config struct {
	// Addr is the TCP address the daemon listens on, e.g. "127.0.0.1:8787".
	Addr string

	// LMStudioBaseURL is the OpenAI-compatible base URL exposed by LM Studio,
	// e.g. "http://localhost:1234/v1".
	LMStudioBaseURL string

	// ChatModel is the model name requested for the advisor chat.
	ChatModel string

	// ContextTokenBudget caps how many tokens of assembled context the daemon
	// will send with a chat request.
	ContextTokenBudget int

	// DataDir, when set, is the base directory for session history
	// (<DataDir>/<project-hash>/sessions). When empty, sessions are stored in
	// each project's own .ami/sessions directory (legacy behaviour).
	DataDir string
}

// Default returns the configuration with all defaults applied.
func Default() Config {
	return Config{
		Addr:               "127.0.0.1:8787",
		LMStudioBaseURL:    "http://localhost:1234/v1",
		ChatModel:          "qwen3-coder",
		ContextTokenBudget: 8000,
	}
}

// Load builds a Config from defaults overlaid with environment variables:
//
//	AMI_ADDR, AMI_LMSTUDIO_URL, AMI_CHAT_MODEL,
//	AMI_CONTEXT_BUDGET, AMI_DATA_DIR
func Load() Config {
	c := Default()
	if v := os.Getenv("AMI_ADDR"); v != "" {
		c.Addr = v
	}
	if v := os.Getenv("AMI_LMSTUDIO_URL"); v != "" {
		c.LMStudioBaseURL = v
	}
	if v := os.Getenv("AMI_CHAT_MODEL"); v != "" {
		c.ChatModel = v
	}
	if v := os.Getenv("AMI_CONTEXT_BUDGET"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			c.ContextTokenBudget = n
		}
	}
	if v := os.Getenv("AMI_DATA_DIR"); v != "" {
		c.DataDir = v
	}
	return c
}
