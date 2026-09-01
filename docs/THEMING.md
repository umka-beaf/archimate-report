## Report theme (RU/EN + light/dark)

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

---

## Русский

Штатный HTML-отчёт Archi функционален, но прост: один фиксированный
английский интерфейс, одна фиксированная светлая тема, а документация
элементов/видов, даже написанная в Markdown, отдаётся сырым текстом.
`USE_MODERN_CSS=true` (по умолчанию — см. [README](../README.md#переменные-окружения))
накладывает тематизированный, локализованный, Markdown-осведомлённый UI
поверх него, не трогая ни одной строки, которую генерирует сам Archi.

### Как это работает

Каждая из (потенциально сотен) страниц, которые генерирует Archi —
`index.html`, `elements/*.html`, `views/*.html` — ссылается ровно на четыре
общих статических файла по фиксированному относительному пути:

```
css/model.css
css/i18n.css
js/model.js
js/frame.js
```

`docker/report-theme/` содержит замену всех четырёх. `generate.sh` копирует
их поверх версий Archi после генерации, прямо перед публикацией отчёта (см.
[`generate.sh`](../docker/generate.sh) и раздел «Тома» в
[README](../README.md#тома) про то, как сама публикация остаётся атомарной).
Поскольку все страницы ссылаются на эти четыре файла, их перезапись
ретематизирует/релокализует весь отчёт разом — без пер-страничного
шаблонирования, без патчинга вывода самого Archi.

### Что в каждом файле

- **`css/i18n.css` + `css/i18n/{en,ru}.css`** — локализация на чистом CSS.
  Строки добавляются/скрываются через `:lang(xx)
  .i18n-someKey:before/:after { content: ... }`, а не через JS-таблицы строк;
  `js/model.js`/`js/frame.js` просто переключают
  `document.documentElement.lang`.
- **`js/frame.js`** — вшивает [marked](https://github.com/markedjs/marked)
  (MIT, v12.0.2, инлайном — тег `<script>` пришлось бы патчить в каждую
  сгенерированную страницу, что сводит на нет весь смысл оверлея из четырёх
  файлов), чтобы рендерить поля **Documentation** элемента/вида/модели как
  Markdown вместо сырого текста. `css/model.css` несёт соответствующие
  `.markdown-body`-стили (заголовки, таблицы, код, blockquote, `<hr>`).
- **`js/model.js`** — переключатель темы/языка в navbar
  (`appendThemeAndLangToggle()`), персистентность через `localStorage`
  (`archi-report-lang`, `archi-report-theme`) с дефолтом от
  `navigator.language`/`prefers-color-scheme`, и автораскрытие только
  верхнего уровня дерева модели (`expandFirstLevel()` — полезно на моделях
  с сотнями элементов, где раскрывать всё сразу непрактично).
- **`css/model.css`** — сами light/dark-палитры, плюс более широкие
  пропорции панели деталей элемента (Documentation/Properties/Analysis) по
  сравнению со штатной раскладкой Archi — чтобы у отрендеренного Markdown
  было достаточно места.

### Отключение

`USE_MODERN_CSS=false` полностью пропускает оверлей — `generate.sh` пишет в
лог, что отдаёт штатный отчёт Archi, и оставляет все четыре файла ровно
такими, какими их сгенерировал сам Archi. Полезно, если нужен оригинальный
вид или если тема переопределяется собственным форком
`docker/report-theme/`.

### Кастомизация

Форкните четыре файла под `docker/report-theme/` и пересоберите образ (см.
«Сборка и публикация образа» в [README](../README.md)) — рантайм-хука для
подмены темы без пересборки нет, намеренно: отчёт и так перегенерируется
целиком при каждом прогоне (см.
[archi#980](https://github.com/archimatetool/archi/issues/980) и валидацию,
которую `generate.sh` делает перед публикацией), так что отдельный механизм
«примонтировать директорию с темой» не даёт выгоды по сравнению с прямым
редактированием исходников.

---

## English

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
stays atomic). Because every page shares these four files, overwriting them
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

### Turning it off

`USE_MODERN_CSS=false` skips the overlay entirely — `generate.sh` logs that
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
