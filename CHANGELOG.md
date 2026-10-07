# Changelog

🇬🇧 English · 🇷🇺 [Русский](CHANGELOG.ru.md)

All notable changes to this project are documented here, one section per
project version (see [docs/VERSIONING.md](docs/VERSIONING.md) for what a
"project version" means and how it relates to the Archi version in the image
tag). This file only calls out what actually changed for someone running the
image, not every commit — see the git history for that level of detail.

## [1.1.1] — dark theme & release pipeline fixes

Bugfix release, no feature changes.

- Fix the dark report theme: panel headers (model tree, view, element
  detail) stayed on Bootstrap's light background because Bootstrap's own
  `.panel-default>.panel-heading` rule outranks a single-class override
  regardless of stylesheet order; also themed the model-tree search box's
  resting (non-focus) state and the Firefox zoom-slider track, both
  previously hidden behind the same bug.
- Fix Archi version resolution (`docker/Dockerfile` and this repo's own
  release workflow): archi.io's release *tag* convention has changed
  shape release to release (dotted, underscored, mixed, and now missing
  the patch digit entirely) and old releases aren't kept around to guess
  against — resolve the version from the release's `name` field instead
  of the tag, and look a pinned version up by matching `name` across the
  releases list rather than guessing a tag shape.
- Pin the `linux/arm64` build's Maven image to the `3.9.x` line
  (`maven:3.9-eclipse-temurin-21`): the floating `maven:3-eclipse-
  temurin-21` tag moved to Maven 3.10.0, whose bundled Maven Resolver 2.x
  rejects the `/`-containing classifier Tycho assigns to system-scoped
  dependencies injected from a bundle's `Bundle-ClassPath` — broke the
  arm64 source build on Archi 5.10.0's new `com.archimatetool.markdown`
  bundle ([eclipse-tycho/tycho#6399](https://github.com/eclipse-tycho/tycho/issues/6399),
  unfixed upstream at the time of this release).
- Caddy now sends `Cache-Control: no-cache` for the report's `.css`/`.js`
  assets. Without it, browsers were free to serve a stale cached copy of
  the theme indefinitely across image upgrades (no explicit freshness
  info meant heuristic caching off `Last-Modified`, which doesn't change
  between builds) — this is why the dark-theme fix above could look like
  it "didn't work" after upgrading until a cache-busted reload.
- Guard the report's cross-frame navigation message handler
  (`js/model.js`) against non-string `postMessage` payloads (e.g. from
  browser extensions or devtools) — it used to throw on anything that
  wasn't its own `"key=id"` format.

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
