## Report theme (RU/EN + light/dark)

🇬🇧 English · 🇷🇺 [Русский](THEMING.ru.md)

---

Archi's HTML report is functional but plain: one fixed English UI, one fixed
light theme, and element/view documentation rendered as raw text even when
it was written as Markdown. `USE_MODERN_CSS=true` (the default — see
[README](../README.md#environment-variables)) layers a themed, localized,
Markdown-aware UI on top of it without touching a single line Archi itself
generates.

### How it works

Every one of the (potentially hundreds of) pages Archi generates —
`index.html`, `elements/*.html`, `views/*.html` — references exactly four
shared static assets by a fixed relative path:

```
css/model.css
css/i18n.css
js/model.js
js/frame.js
```

`docker/report-theme/` ships replacements for all four. `generate.sh` copies
them over Archi's own versions after generation, right before the report is
published (see [`generate.sh`](../docker/generate.sh) and the "Volumes"
section in the [README](../README.md#volumes) for how publishing itself
works). Because every page shares these four files, overwriting them
re-themes/re-localizes the entire report at once — no per-page templating,
no patching Archi's own output.

### What's in each file

- **`css/i18n.css` + `css/i18n/{en,ru}.css`** — pure-CSS localization.
  Strings are added/hidden via `:lang(xx) .i18n-someKey:before/:after { content: ... }`
  rather than JS string tables; `js/model.js`/`js/frame.js` just flip
  `document.documentElement.lang`.
- **`js/frame.js`** — bundles [marked](https://github.com/markedjs/marked)
  (MIT, v12.0.2, vendored inline — a `<script>` tag would need patching every
  generated page, which defeats the point of a four-file overlay) to render
  element/view/model **Documentation** fields as Markdown instead of raw
  text. `css/model.css` carries the matching `.markdown-body` styles
  (headings, tables, code, blockquotes, `<hr>`).
- **`js/model.js`** — theme/language toggle in the navbar
  (`appendThemeAndLangToggle()`), `localStorage`-backed preferences
  (`archi-report-lang`, `archi-report-theme`) defaulting from
  `navigator.language`/`prefers-color-scheme`, and auto-expanding just the
  top level of the model tree (`expandFirstLevel()` — useful on models with
  hundreds of elements, where expanding everything by default isn't
  practical).
- **`css/model.css`** — the actual light/dark palettes, plus wider panel
  proportions for the element detail pane (Documentation/Properties/
  Analysis) than Archi's stock layout, to give rendered Markdown enough
  room.

### Favicon

Archi's stock report ships no favicon at all. `assets/favicon/`
(`favicon.ico` + PNGs at 16/32/48/192/512px, plus a 180px `apple-touch-icon.png`
— all rasterized from `assets/favicon/favicon.svg`, the square "mark" half of
the main `assets/logo.svg`, without the text) is this repo's single source of
truth for these files; the `Dockerfile` copies them straight from there into
`/opt/report-theme/favicon/` at image build time (the build context is the
repo root, not `docker/`, specifically so this `COPY` can reach them) — no
second, hand-synced copy lives under `docker/report-theme/`. `generate.sh`
then copies them into the report root **regardless of `USE_MODERN_CSS`** — browsers request
`/favicon.ico` off the server root implicitly even without an explicit
`<link>` tag, so the icon shows up either way. `js/model.js` (themed build
only) additionally injects explicit `<link rel="icon"/apple-touch-icon">` tags
into `index.html` (the only top-level page — `elements/*.html` and
`views/*.html` load inside an `<iframe>` via `frame.js`, whose favicon a
browser tab never shows), so modern browsers/OSes pick the higher-res PNGs
over the bare `.ico`.

### Turning it off

`USE_MODERN_CSS=false` skips the CSS/JS overlay entirely (the favicon stays —
see above) — `generate.sh` logs that
it's serving Archi's stock report and leaves the four files exactly as Archi
generated them. Useful if you want the original look, or if you're
overriding the theme with your own fork of `docker/report-theme/`.

### Customizing

Fork the four files under `docker/report-theme/` and rebuild the image (see
"Building and publishing the image" in the [README](../README.md)) — there's
no runtime hook for swapping them without a rebuild, by design: the report is
regenerated wholesale on every run anyway (see
[archi#980](https://github.com/archimatetool/archi/issues/980) and the
validation `generate.sh` does before publishing), so there's no benefit to a
separate mount-a-theme-directory mechanism over just editing the source.
