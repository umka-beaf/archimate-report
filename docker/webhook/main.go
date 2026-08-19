// archi-webhook is a small HTTP listener that triggers /usr/local/bin/generate.sh
// on an incoming, authenticated webhook. It does not duplicate any git/model
// logic — generate.sh already knows how to clone/generate from the container's
// GIT_*/MODEL_* environment, so this binary only owns: request auth
// (WEBHOOK_PROVIDER-driven), a single-slot debounce queue so pushes never
// overlap generations, and a /status endpoint for observability.
//
// It listens on 127.0.0.1:8088 only — Caddy is the one public-facing process
// (see ../Caddyfile), reverse-proxying /webhook* and /status here.
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

const listenAddr = "127.0.0.1:8088"

// State tracks generation status and implements the single-slot debounce
// queue: at most one generate.sh runs at a time; a webhook that arrives
// while one is running just sets pending=true so the run repeats once more
// after the current one finishes, instead of running in parallel.
type State struct {
	mu          sync.Mutex
	running     bool
	pending     bool
	lastRunAt   time.Time
	lastSuccess bool
	lastError   string
}

func (s *State) snapshot() (generating bool, lastRunAt time.Time, lastSuccess bool, lastError string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.running, s.lastRunAt, s.lastSuccess, s.lastError
}

// trigger requests a generation run. If one is already in flight it just
// marks pending and returns — the in-flight run's loop will pick it up.
func (s *State) trigger() {
	s.mu.Lock()
	if s.running {
		s.pending = true
		s.mu.Unlock()
		return
	}
	s.running = true
	s.mu.Unlock()

	go s.runLoop()
}

// runLoop runs generate.sh, then re-runs it as long as another trigger()
// arrived while it was working. A loop (not recursion) keeps the stack flat
// under a burst of pushes.
func (s *State) runLoop() {
	for {
		err := runGenerateOnce()

		s.mu.Lock()
		s.lastRunAt = time.Now().UTC()
		if err != nil {
			s.lastSuccess = false
			s.lastError = err.Error()
		} else {
			s.lastSuccess = true
			s.lastError = ""
		}

		if s.pending {
			s.pending = false
			s.mu.Unlock()
			continue
		}
		s.running = false
		s.mu.Unlock()
		return
	}
}

func runGenerateOnce() error {
	cmd := exec.Command("/usr/local/bin/generate.sh")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	log.Printf("[webhook] running generate.sh")
	if err := cmd.Run(); err != nil {
		log.Printf("[webhook] generate.sh failed: %v", err)
		return err
	}
	log.Printf("[webhook] generate.sh succeeded")
	return nil
}

// verifyGitHub checks the GitHub-style X-Hub-Signature-256 header:
// "sha256=<hex hmac of body with secret>".
func verifyGitHub(secret string, body []byte, sigHeader string) bool {
	const prefix = "sha256="
	if !strings.HasPrefix(sigHeader, prefix) {
		return false
	}
	sigHex := strings.TrimPrefix(sigHeader, prefix)
	sig, err := hex.DecodeString(sigHex)
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	expected := mac.Sum(nil)
	return hmac.Equal(sig, expected)
}

// verifyGitLab checks the GitLab-style X-Gitlab-Token header: a direct
// secret comparison (GitLab does not HMAC the body), done constant-time.
func verifyGitLab(secret, tokenHeader string) bool {
	if tokenHeader == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(tokenHeader), []byte(secret)) == 1
}

// verifyGeneric accepts either an X-Webhook-Secret header or a ?secret=
// query parameter, compared constant-time. Used for providers with no
// specific signature scheme.
func verifyGeneric(secret string, r *http.Request) bool {
	candidate := r.Header.Get("X-Webhook-Secret")
	if candidate == "" {
		candidate = r.URL.Query().Get("secret")
	}
	if candidate == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(candidate), []byte(secret)) == 1
}

func makeWebhookHandler(state *State, secret, provider string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "failed to read body", http.StatusBadRequest)
			return
		}

		var ok bool
		switch provider {
		case "github":
			ok = verifyGitHub(secret, body, r.Header.Get("X-Hub-Signature-256"))
		case "gitlab":
			ok = verifyGitLab(secret, r.Header.Get("X-Gitlab-Token"))
		case "generic":
			ok = verifyGeneric(secret, r)
		}

		if !ok {
			log.Printf("[webhook] rejected: bad signature (provider=%s)", provider)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		state.trigger()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"status":"accepted"}`))
	}
}

func handleStatus(state *State) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		generating, lastRunAt, lastSuccess, lastError := state.snapshot()

		resp := struct {
			Generating  bool    `json:"generating"`
			LastRunAt   *string `json:"last_run_at"`
			LastSuccess bool    `json:"last_success"`
			LastError   string  `json:"last_error"`
		}{
			Generating:  generating,
			LastSuccess: lastSuccess,
			LastError:   lastError,
		}
		if !lastRunAt.IsZero() {
			s := lastRunAt.Format(time.RFC3339)
			resp.LastRunAt = &s
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(resp)
	}
}

func main() {
	secret := os.Getenv("WEBHOOK_SECRET")
	provider := os.Getenv("WEBHOOK_PROVIDER")
	path := os.Getenv("WEBHOOK_PATH")
	if path == "" {
		path = "/webhook"
	}

	if secret != "" {
		switch provider {
		case "github", "gitlab", "generic":
			// ok
		default:
			log.Fatalf("[webhook] WEBHOOK_SECRET is set but WEBHOOK_PROVIDER=%q is not one of github|gitlab|generic", provider)
		}
	}

	state := &State{}
	mux := http.NewServeMux()
	mux.HandleFunc("/status", handleStatus(state))

	if secret != "" {
		mux.HandleFunc(path, makeWebhookHandler(state, secret, provider))
		log.Printf("[webhook] listening on %s, webhook path=%s provider=%s", listenAddr, path, provider)
	} else {
		log.Printf("[webhook] WEBHOOK_SECRET not set, /webhook disabled (listening on %s for /status only)", listenAddr)
	}

	if err := http.ListenAndServe(listenAddr, mux); err != nil {
		log.Fatalf("[webhook] server failed: %v", fmt.Errorf("%w", err))
	}
}
