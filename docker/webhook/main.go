// archi-webhook is a small HTTP listener that triggers /usr/local/bin/generate.sh
// on an incoming, authenticated webhook. It does not duplicate any git/model
// logic — generate.sh already knows how to clone/generate from the container's
// GIT_*/MODEL_* environment, so this binary only owns: request auth
// (WEBHOOK_PROVIDER-driven), a debounced generation queue, and /status
// endpoints for observability.
//
// It listens on 127.0.0.1:8088 only — Caddy is the one public-facing process
// (see ../Caddyfile), reverse-proxying /webhook*, /status, /*/webhook and
// /*/status here.
//
// Multi-model support (CLAUDE.md §32/§33.1, M6.4): if any MODEL_<N>_SLUG env
// vars are present, this binary switches into multi-model mode — one route
// pair (/<slug>/webhook, /<slug>/status) per discovered model, all sharing a
// single WEBHOOK_SECRET/WEBHOOK_PROVIDER (§32.1: one owner, one secret is an
// accepted trade-off) and a single global sequential generation worker with
// per-slug debounce (§32.5). Legacy single-model mode (no MODEL_<N>_SLUG
// vars found) is unchanged from M3: /webhook and /status, no slug involved.
// Internally both modes are the same machinery with slug="" standing in for
// "the one legacy model" — see the `model` type and `newState` below.
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const listenAddr = "127.0.0.1:8088"

// logf/fatalf print the same "<UTC RFC3339> [component] message" prefix as
// entrypoint.sh and generate.sh's log() functions, so `docker logs` output
// from all three processes sorts/greps consistently. Not the stdlib "log"
// package because its flag-based formats (Ldate|Ltime, LUTC, ...) can't
// produce this exact "2006-01-02T15:04:05Z" shape.
func logf(format string, args ...any) {
	ts := time.Now().UTC().Format("2006-01-02T15:04:05Z")
	fmt.Fprintf(os.Stderr, ts+" "+format+"\n", args...)
}

func fatalf(format string, args ...any) {
	logf(format, args...)
	os.Exit(1)
}

// model identifies one configured model: slug is its URL path segment,
// index is the MODEL_<index>_* env-var suffix to pass to generate.sh. In
// legacy single-model mode there is exactly one model with slug="" and
// index="" (meaning: call generate.sh with no MODEL_INDEX argument at all,
// same as before M6).
type model struct {
	slug  string
	index string
}

var (
	modelSlugVarRe = regexp.MustCompile(`^MODEL_([0-9]+)_SLUG$`)
	slugValidRe    = regexp.MustCompile(`^[A-Za-z0-9-]+$`)
)

// discoverModels scans the environment for MODEL_<N>_SLUG vars the same way
// docker/lib/model-config.sh's mc_model_indices() does for the shell side
// (§32.1) — same validation, same error conditions. This duplicates that
// bash logic rather than shelling out to it: archi-webhook is a standalone
// long-running process, not a per-request script, and by the time it starts
// entrypoint.sh has already validated the exact same environment via
// mc_model_indices — so these fatalf paths are normally unreachable, kept
// only so this binary is self-contained/robust on its own if ever invoked
// outside that sequence. Returns nil (not an error) when no MODEL_<N>_SLUG
// vars are found — legacy mode.
func discoverModels() []model {
	type found struct {
		n    int
		slug string
	}
	seenSlugs := map[string]int{}
	var models []found

	for _, kv := range os.Environ() {
		eq := strings.IndexByte(kv, '=')
		if eq < 0 {
			continue
		}
		name := kv[:eq]
		m := modelSlugVarRe.FindStringSubmatch(name)
		if m == nil {
			continue
		}
		n, _ := strconv.Atoi(m[1]) // regexp already guarantees digits
		slug := os.Getenv(name)
		if slug == "" {
			fatalf("[webhook] MODEL_%d_SLUG is set but empty", n)
		}
		if !slugValidRe.MatchString(slug) {
			fatalf("[webhook] MODEL_%d_SLUG=%q is invalid — only ASCII letters, digits, and hyphens are allowed", n, slug)
		}
		if prevN, ok := seenSlugs[slug]; ok {
			fatalf("[webhook] duplicate slug %q: used by both MODEL_%d_SLUG and MODEL_%d_SLUG", slug, prevN, n)
		}
		seenSlugs[slug] = n
		models = append(models, found{n: n, slug: slug})
	}

	sort.Slice(models, func(i, j int) bool { return models[i].n < models[j].n })

	result := make([]model, len(models))
	for i, f := range models {
		result[i] = model{slug: f.slug, index: strconv.Itoa(f.n)}
	}
	return result
}

// modelStatus mirrors the JSON shape /status has returned since M3 (§19) —
// kept unchanged for legacy-mode backward compatibility, and reused verbatim
// per-slug in multi-model mode.
type modelStatus struct {
	lastRunAt   time.Time
	lastSuccess bool
	lastError   string
}

// State implements one global sequential generation worker shared by every
// configured model, with per-slug debounce (§32.5): at most one generate.sh
// runs at a time across the whole process; triggering a slug that's already
// queued (waiting or currently running) is a no-op — it doesn't queue a
// second entry — so a burst of pushes for the same model collapses to at
// most one more run after the current one finishes. Different slugs queue
// independently and are processed strictly in FIFO order, never in
// parallel — simpler and more predictable than a worker per model, at the
// cost of one busy model's queue delaying another's (accepted trade-off,
// see §32.5: "parallel generation... deliberately postponed").
type State struct {
	mu          sync.Mutex
	running     bool
	currentSlug string
	queue       []string
	queued      map[string]bool
	statuses    map[string]*modelStatus

	// indexOf maps slug -> MODEL_<index> suffix (or "" in legacy mode).
	// Populated once at startup by newState and never written again, so the
	// worker goroutine can read it without holding mu.
	indexOf map[string]string
}

func newState(models []model) *State {
	s := &State{
		queued:   make(map[string]bool),
		statuses: make(map[string]*modelStatus),
		indexOf:  make(map[string]string),
	}
	for _, m := range models {
		s.statuses[m.slug] = &modelStatus{}
		s.indexOf[m.slug] = m.index
	}
	return s
}

// snapshot returns the current status for one slug. "generating" is true
// from the moment a trigger for this slug is accepted until its (possibly
// repeated, via debounce) run(s) fully settle — i.e. true both while queued
// and while actively running, matching the pre-M6.4 single-model semantics
// where /status.generating covered the whole debounce cycle, not just the
// active subprocess.
func (s *State) snapshot(slug string) (generating bool, lastRunAt time.Time, lastSuccess bool, lastError string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	generating = s.queued[slug] || (s.running && s.currentSlug == slug)
	st := s.statuses[slug]
	if st != nil {
		lastRunAt, lastSuccess, lastError = st.lastRunAt, st.lastSuccess, st.lastError
	}
	return
}

// anyGenerating reports whether the worker is doing anything at all, for the
// simplified multi-model root /status (§32.4/M6.4: deliberately no per-slug
// detail there, to avoid using the root path to enumerate which slugs are
// currently active).
func (s *State) anyGenerating() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.running
}

// trigger requests a generation run for slug. If slug is already queued
// (whether waiting or currently the one running) this is a no-op — that's
// the per-slug debounce. Otherwise it's appended to the FIFO queue, and the
// worker goroutine is started if it isn't already running.
func (s *State) trigger(slug string) {
	s.mu.Lock()
	if s.queued[slug] {
		s.mu.Unlock()
		return
	}
	s.queued[slug] = true
	s.queue = append(s.queue, slug)
	startWorker := !s.running
	if startWorker {
		s.running = true
	}
	s.mu.Unlock()

	if startWorker {
		go s.workerLoop()
	}
}

// workerLoop is the single global sequential worker (§32.5): pop the next
// queued slug, run generate.sh for it, record the result, repeat until the
// queue is empty. A loop (not recursion) keeps the stack flat under a burst
// of triggers across many slugs.
func (s *State) workerLoop() {
	for {
		s.mu.Lock()
		if len(s.queue) == 0 {
			s.running = false
			s.currentSlug = ""
			s.mu.Unlock()
			return
		}
		slug := s.queue[0]
		s.queue = s.queue[1:]
		delete(s.queued, slug)
		s.currentSlug = slug
		index := s.indexOf[slug]
		s.mu.Unlock()

		err := runGenerateOnce(slug, index)

		s.mu.Lock()
		st := s.statuses[slug]
		if st == nil {
			st = &modelStatus{}
			s.statuses[slug] = st
		}
		st.lastRunAt = time.Now().UTC()
		if err != nil {
			st.lastSuccess = false
			st.lastError = err.Error()
		} else {
			st.lastSuccess = true
			st.lastError = ""
		}
		s.mu.Unlock()
	}
}

// runGenerateOnce runs generate.sh for one model. In legacy mode (slug=="")
// it's called with no arguments, exactly as before M6.4; in multi-model mode
// it's passed index as generate.sh's documented MODEL_INDEX argument (see
// the "Usage: generate.sh [MODEL_INDEX]" docstring in generate.sh).
func runGenerateOnce(slug, index string) error {
	tag := "[webhook]"
	if slug != "" {
		tag = fmt.Sprintf("[webhook:%s]", slug)
	}

	// Tee stderr into a small buffer alongside the normal docker-logs stream,
	// so a failure's /status.last_error can carry generate.sh's actual
	// diagnostic line (e.g. "die: ...") instead of just Go's generic
	// "exit status 1" — that string alone told an operator nothing without
	// also going to grep docker logs.
	var stderrBuf strings.Builder
	var args []string
	if index != "" {
		args = append(args, index)
	}
	cmd := exec.Command("/usr/local/bin/generate.sh", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderrBuf)
	logf("%s running generate.sh", tag)
	if err := cmd.Run(); err != nil {
		logf("%s generate.sh failed: %v", tag, err)
		return fmt.Errorf("%v: %s", err, lastNonEmptyLine(stderrBuf.String()))
	}
	logf("%s generate.sh succeeded", tag)
	return nil
}

// lastNonEmptyLine returns the last non-blank line of s, truncated to a
// reasonable length for a JSON status field. generate.sh's die() writes its
// message as the final stderr line before exiting (prefixed "ERROR: ..."),
// so this is normally the actual human-readable reason for the failure
// rather than raw Java stack-trace noise.
func lastNonEmptyLine(s string) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			continue
		}
		const maxLen = 300
		if len(line) > maxLen {
			line = line[:maxLen] + "…"
		}
		return line
	}
	return "(no diagnostic output captured)"
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

func makeWebhookHandler(state *State, secret, provider, slug string) http.HandlerFunc {
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
			logf("[webhook] rejected: bad signature (provider=%s, slug=%q)", provider, slug)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		state.trigger(slug)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"status":"accepted"}`))
	}
}

// handleStatus serves the full per-model JSON shape unchanged since M3
// (§19) — used for legacy mode's /status and, in multi-model mode, each
// model's /<slug>/status.
func handleStatus(state *State, slug string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		generating, lastRunAt, lastSuccess, lastError := state.snapshot(slug)

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

// handleRootStatusMulti serves the simplified, boolean-only root /status in
// multi-model mode (M6.4) — deliberately just "is anything generating right
// now", with no per-slug breakdown (which model, its last error, etc. — that
// detail lives at /<slug>/status, reachable only if you already know the
// slug). Keeps the root path from becoming a way to enumerate/fingerprint
// which models exist, consistent with §32.4's stub-page rationale.
func handleRootStatusMulti(state *State) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		resp := struct {
			Generating bool `json:"generating"`
		}{Generating: state.anyGenerating()}
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
			fatalf("[webhook] WEBHOOK_SECRET is set but WEBHOOK_PROVIDER=%q is not one of github|gitlab|generic", provider)
		}
	}

	models := discoverModels()
	mux := http.NewServeMux()

	if len(models) == 0 {
		// Legacy single-model mode (§32.2) — unchanged from M3.
		state := newState([]model{{slug: "", index: ""}})
		mux.HandleFunc("/status", handleStatus(state, ""))
		if secret != "" {
			mux.HandleFunc(path, makeWebhookHandler(state, secret, provider, ""))
			logf("[webhook] listening on %s, webhook path=%s provider=%s", listenAddr, path, provider)
		} else {
			logf("[webhook] WEBHOOK_SECRET not set, /webhook disabled (listening on %s for /status only)", listenAddr)
		}
	} else {
		// Multi-model mode (§32/M6.4) — one /<slug>/webhook + /<slug>/status
		// pair per discovered model, sharing one WEBHOOK_SECRET/PROVIDER and
		// one sequential worker (State). WEBHOOK_PATH is not consulted here —
		// per §32.1 it has no meaning once slugs are in play, the webhook
		// path is always /<slug>/webhook.
		state := newState(models)
		mux.HandleFunc("/status", handleRootStatusMulti(state))

		slugs := make([]string, 0, len(models))
		for _, m := range models {
			slugs = append(slugs, m.slug)
			mux.HandleFunc("/"+m.slug+"/status", handleStatus(state, m.slug))
			if secret != "" {
				mux.HandleFunc("/"+m.slug+"/webhook", makeWebhookHandler(state, secret, provider, m.slug))
			}
		}
		if secret != "" {
			logf("[webhook] listening on %s, multi-model mode: %d model(s) (%s), provider=%s", listenAddr, len(models), strings.Join(slugs, ", "), provider)
		} else {
			logf("[webhook] WEBHOOK_SECRET not set, per-model webhooks disabled (listening on %s for /status and /<slug>/status only): %s", listenAddr, strings.Join(slugs, ", "))
		}
	}

	if err := http.ListenAndServe(listenAddr, mux); err != nil {
		fatalf("[webhook] server failed: %v", fmt.Errorf("%w", err))
	}
}
