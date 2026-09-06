# Changelog

🇬🇧 English · 🇷🇺 [Русский](CHANGELOG.ru.md)

All notable changes to this project are documented here, one section per
project version (see [docs/VERSIONING.md](docs/VERSIONING.md) for what a
"project version" means and how it relates to the Archi version in the image
tag). This file only calls out what actually changed for someone running the
image, not every commit — see the git history for that level of detail.

## [1.1.0] — multi-model support

**Highlight: one container instance can now serve reports for several
independent ArchiMate models at once**, each on its own path
(`/<slug>/...`), configured via indexed `MODEL_<N>_*` environment variables.
This is a significant capability change, not a bugfix — see
[docs/MULTI_MODEL.md](docs/MULTI_MODEL.md) for the full configuration
reference and [docs/SECURITY.md](docs/SECURITY.md) for the path-based
forward-auth pattern this unlocks.

- Add multi-model configuration: `MODEL_<N>_SLUG` and per-model
  `GIT_*`/`MODEL_*`/auth variables, auto-detected from the environment (no
  `MODEL_COUNT` to maintain).
- Add per-slug report paths, root placeholder page, and "not generated yet"
  stub pages that don't leak which slugs exist to unauthenticated visitors.
- Add per-slug webhook (`/<slug>/webhook`) and status (`/<slug>/status`)
  endpoints, backed by a single sequential generation worker with per-slug
  debounce.
- Single-model ("legacy") configuration continues to work unchanged if no
  `MODEL_<N>_SLUG` variables are set.

## [1.0.0] — initial release

Everything shipped before multi-model support: cloning a plain `.archimate`
file or a coArchi repository, generating the HTML report via the Archi CLI,
serving it through Caddy, webhook-triggered regeneration
(GitHub/GitLab/generic signature schemes), the RU/EN light/dark report theme
(`USE_MODERN_CSS`), native `linux/arm64` build (no emulation), healthcheck,
and git operation retries/timeouts.
