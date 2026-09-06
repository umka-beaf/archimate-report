# Security: authentication & authorization

🇬🇧 English · 🇷🇺 [Русский](SECURITY.ru.md)

---

### The service does not authenticate visitors itself

There's no login, no API key, no user model anywhere in this project. This
is deliberate: the intended deployment already sits
behind a reverse proxy that does forward-auth (Caddy + Authentik, in the
setup this design was written for), and a per-path auth rule is a natural
fit for [multi-model mode](MULTI_MODEL.md), where different stakeholders
should see different models. Baking a second, redundant auth layer into the
container itself would only create two things to keep in sync and two
places for a misconfiguration to hide.

### Recommended pattern: Caddy/Authentik forward-auth by path

```caddyfile
example.com {
    @needs_auth not path /*/webhook
    handle @needs_auth {
        forward_auth authentik:9000 {
            uri /outpost.goauthentik.io/auth/caddy
            copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
    }
    reverse_proxy archimate-report:3000
}
```

Put whatever path-based authorization rules you need on top of this (e.g.
requiring a specific Authentik group for `/finance-model/*`) — that's
entirely between your proxy and your identity provider, this project has no
opinion on it beyond "don't break the webhook" (see below).

### Critical: don't wrap `/<slug>/webhook` in the shared auth rule

Git providers (GitHub, GitLab, ...) send webhook requests directly — they
never go through your SSO login flow, so a forward-auth rule applied to all
of `/<slug>/*` will silently turn every webhook into a `401`/`302`-to-login,
and the report will simply stop updating without an obvious error on your
side (see [docs/WEBHOOK.md](WEBHOOK.md) for what a healthy webhook request
looks like). `/<slug>/webhook` is already protected by its own
`WEBHOOK_SECRET` check — it doesn't need, and must not have, the shared
proxy-level auth in front of it. `/<slug>/status` is a judgment call: it
leaks no model content, only generation status, so it's reasonable to leave
it open alongside the webhook if that's simpler for your setup.

### A shared `WEBHOOK_SECRET` across all models — an accepted trade-off

The service has a single owner (see [docs/MULTI_MODEL.md](MULTI_MODEL.md)),
so one webhook secret and one `WEBHOOK_PROVIDER` apply to every model in a given instance
— there's no per-model secret. If you need cryptographically distinct
secrets per model (e.g. because different teams manage different upstream
repositories and shouldn't be able to trigger each other's regeneration),
run separate container instances rather than relying on this project to
partition trust within a single instance.

### What's NOT considered a threat in this model

- Someone guessing a model's slug and hitting `/<slug>/` directly — the
  `/` and `/<slug>/` placeholder pages (see
  [docs/MULTI_MODEL.md](MULTI_MODEL.md)) avoid *advertising* the list of
  slugs, but that's a defense against casual discovery, not a guarantee of
  unlinkability. Put real access control (the forward-auth rule above) in
  front of anything actually sensitive.
- Anyone with `WEBHOOK_SECRET` triggering regeneration for *any* model in
  the instance, not just "their" model — this follows directly from the
  shared-secret design above and is the reason for the "separate instances
  for separate trust boundaries" recommendation.
