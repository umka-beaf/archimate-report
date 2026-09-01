# archimate-report

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

Docker-образ, который клонирует git-репозиторий с ArchiMate-моделью, генерирует
HTML-отчёт через Archi CLI и раздаёт его статикой. Поддерживает вебхук для
перегенерации по пушу. Multi-arch: `linux/amd64` + `linux/arm64` — обе
архитектуры собраны нативно (arm64 — из исходников Archi, никакой эмуляции в
рантайме).

🥧 **Killer-фича: Archi наконец-то запускается на Raspberry Pi** — официальной
Linux ARM64-сборки не существует, мы собираем её нативно из исходников.
📝 Плюс RU/EN + light/dark тема отчёта с рендерингом документации элементов
как Markdown, а не сырого текста (`USE_MODERN_CSS`).

🥧 **Killer feature: Archi finally runs on a Raspberry Pi** — no official
Linux ARM64 build exists, so we build one natively from source.
📝 Plus an RU/EN + light/dark report theme that renders element documentation
as Markdown instead of raw text (`USE_MODERN_CSS`).

---

<a id="русский"></a>
## 🇷🇺 Русский

### Что делает

1. При старте контейнера клонирует git-репозиторий с ArchiMate-моделью —
   одиночный `*.archimate`-файл или coArchi-репозиторий (автоопределение
   формата).
2. Прогоняет модель через официальный [Archi CLI](https://github.com/archimatetool/archi/wiki/Archi-Command-Line-Interface)
   и генерирует HTML-отчёт.
3. Раздаёт отчёт статикой через Caddy на порту `3000`.
4. Опционально принимает вебхук (`github`/`gitlab`/`generic`) для
   перегенерации отчёта по пушу в репозиторий модели.

### Быстрый старт

```bash
docker run -d \
  --name archimate-report \
  -p 3000:3000 \
  -e GIT_URL=https://github.com/your-org/your-model-repo.git \
  -e GIT_TOKEN=ghp_xxx \
  umkabeaf/archimate-report:latest
```

Отчёт будет доступен на `http://localhost:3000` через несколько секунд после
старта (первая генерация выполняется синхронно перед запуском веб-сервера).

### Переменные окружения

| Переменная | Обязательна | Описание |
|---|---|---|
| `GIT_URL` | да | URL репозитория (`https://` или `git@...`) |
| `GIT_REF` | нет | ветка/тег/коммит, по умолчанию — HEAD дефолтной ветки |
| `MODEL_PATH` | нет | путь к `.archimate`-файлу или корню coArchi-репозитория, если авто-детект неоднозначен |
| `MODEL_FORMAT` | нет | `auto` (по умолчанию) / `plain` / `coarchi` |
| `GIT_TOKEN` | нет* | HTTPS-токен (PAT) |
| `GIT_USERNAME` / `GIT_PASSWORD` | нет* | логин+пароль для HTTPS |
| `GIT_SSH_PRIVATE_KEY` | нет* | приватный SSH-ключ (PEM или base64) ⚠️ пока не протестировано end-to-end |
| `GIT_SSH_KNOWN_HOSTS` | нет | содержимое known_hosts; без него — TOFU (`accept-new`) |
| `WEBHOOK_SECRET` | нет | если задан — включает `/webhook` |
| `WEBHOOK_PROVIDER` | нет** | `github` / `gitlab` / `generic` — обязателен, если задан `WEBHOOK_SECRET` |
| `WEBHOOK_PATH` | нет | путь эндпоинта, по умолчанию `/webhook` |
| `PORT` | нет | порт раздачи, по умолчанию `3000` |
| `REGENERATE_ON_START` | нет | `true` (по умолчанию) / `false` |
| `GENERATION_TIMEOUT` | нет | таймаут одного прогона генерации, сек (по умолчанию `600`) |
| `USE_MODERN_CSS` | нет | `true` (по умолчанию) / `false` — RU/EN + light/dark тема отчёта поверх штатного Archi-вида; `false` отдаёт немодифицированный отчёт Archi |
| `TZ` | нет | таймзона контейнера |

`*` — ровно один способ авторизации git (или ни одного — для публичных
репозиториев). `**` — обязательна только вместе с `WEBHOOK_SECRET`.

`GET /status` (тот же порт, что и отчёт) отдаёт JSON
`{generating, last_run_at, last_success, last_error}` — используется как
healthcheck.

### Тома

Три рабочие директории, ни одна не объявлена `VOLUME` в образе — без явного
монтирования это обычные слои контейнера, не переживающие `docker rm`:

| Путь | Назначение | Монтировать? |
|---|---|---|
| `/data/report` | Готовый HTML-отчёт, который раздаёт Caddy | Да, если хотите, чтобы отчёт пережил пересоздание контейнера — особенно вместе с `REGENERATE_ON_START=false` |
| `/data/repo` | Рабочая копия git-репозитория с моделью | Опционально — ускоряет повторные запуски (`git fetch` вместо полного `clone`) |
| `/data/secrets` | Временные файлы авторизации (SSH-ключ/токен/пароль), права `600` | Нет — создаются заново из env-переменных при каждом запуске, монтирование только продлевает жизнь секретов на диске |

```bash
docker run -d \
  --name archimate-report \
  -p 3000:3000 \
  -v archimate-report-data:/data/report \
  -e GIT_URL=https://github.com/your-org/your-model-repo.git \
  -e GIT_TOKEN=ghp_xxx \
  -e REGENERATE_ON_START=false \
  umkabeaf/archimate-report:latest
```

### Теги образа

- `:latest` — последняя опубликованная версия.
- `:<версия Archi>` (например `:5.9.0`) — конкретная версия Archi, зашитая в
  образ; фиксируйте её в продакшене вместо `:latest`.

Оба тега для одной публикации указывают на один и тот же multi-arch manifest
list (amd64 + arm64) — не расходятся между собой.

### Архитектуры

- `linux/amd64` — официальная сборка Archi (`Archi-Linux64-*.tgz`).
- `linux/arm64` — Archi собран нативно из исходников (Tycho/Maven,
  `linux/gtk/aarch64`) в момент сборки образа. Никакого QEMU/box64 в
  рантайме — только на этапе `docker buildx build` для кросс-компиляции,
  сам работающий контейнер полностью нативный на обеих архитектурах.

---

<a id="english"></a>
## 🇬🇧 English

### What it does

1. On container start, clones a git repository containing an ArchiMate model —
   a single `*.archimate` file or a coArchi repository (format auto-detected).
2. Runs the model through the official [Archi CLI](https://github.com/archimatetool/archi/wiki/Archi-Command-Line-Interface)
   to generate an HTML report.
3. Serves the report as static files via Caddy on port `3000`.
4. Optionally accepts a webhook (`github`/`gitlab`/`generic`) to regenerate
   the report on a push to the model repository.

### Quick start

```bash
docker run -d \
  --name archimate-report \
  -p 3000:3000 \
  -e GIT_URL=https://github.com/your-org/your-model-repo.git \
  -e GIT_TOKEN=ghp_xxx \
  umkabeaf/archimate-report:latest
```

The report is available at `http://localhost:3000` a few seconds after start
(the first generation runs synchronously before the web server comes up).

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `GIT_URL` | yes | Repository URL (`https://` or `git@...`) |
| `GIT_REF` | no | branch/tag/commit, defaults to the default branch's HEAD |
| `MODEL_PATH` | no | path to the `.archimate` file or coArchi repo root, if auto-detection is ambiguous |
| `MODEL_FORMAT` | no | `auto` (default) / `plain` / `coarchi` |
| `GIT_TOKEN` | no* | HTTPS token (PAT) |
| `GIT_USERNAME` / `GIT_PASSWORD` | no* | login+password for HTTPS |
| `GIT_SSH_PRIVATE_KEY` | no* | private SSH key (PEM or base64) ⚠️ not tested end-to-end yet |
| `GIT_SSH_KNOWN_HOSTS` | no | known_hosts content; without it — TOFU (`accept-new`) |
| `WEBHOOK_SECRET` | no | if set, enables `/webhook` |
| `WEBHOOK_PROVIDER` | no** | `github` / `gitlab` / `generic` — required if `WEBHOOK_SECRET` is set |
| `WEBHOOK_PATH` | no | endpoint path, defaults to `/webhook` |
| `PORT` | no | serving port, defaults to `3000` |
| `REGENERATE_ON_START` | no | `true` (default) / `false` |
| `GENERATION_TIMEOUT` | no | timeout for a single generation run, seconds (default `600`) |
| `USE_MODERN_CSS` | no | `true` (default) / `false` — RU/EN + light/dark report theme layered on Archi's stock look; `false` serves Archi's unmodified report |
| `TZ` | no | container timezone |

`*` — exactly one git auth method (or none, for public repositories).
`**` — required only together with `WEBHOOK_SECRET`.

`GET /status` (same port as the report) returns JSON
`{generating, last_run_at, last_success, last_error}` — used as the
healthcheck.

### Volumes

Three working directories; none are declared as `VOLUME` in the image — without
explicit mounting they're ordinary container layers that don't survive
`docker rm`:

| Path | Purpose | Mount it? |
|---|---|---|
| `/data/report` | Finished HTML report, served by Caddy | Yes, if you want the report to survive container recreation — especially with `REGENERATE_ON_START=false` |
| `/data/repo` | Working copy of the model's git repository | Optional — speeds up subsequent runs (`git fetch` instead of a full `clone`) |
| `/data/secrets` | Temporary auth material (SSH key/token/password), `600` perms | No — recreated from env vars on every run; mounting it only extends how long secrets sit on disk |

```bash
docker run -d \
  --name archimate-report \
  -p 3000:3000 \
  -v archimate-report-data:/data/report \
  -e GIT_URL=https://github.com/your-org/your-model-repo.git \
  -e GIT_TOKEN=ghp_xxx \
  -e REGENERATE_ON_START=false \
  umkabeaf/archimate-report:latest
```

### Image tags

- `:latest` — the most recently published version.
- `:<Archi version>` (e.g. `:5.9.0`) — a specific Archi version baked into the
  image; pin this in production instead of `:latest`.

Both tags from a given release point at the same multi-arch manifest list
(amd64 + arm64) — they never drift apart.

### Architectures

- `linux/amd64` — official Archi build (`Archi-Linux64-*.tgz`).
- `linux/arm64` — Archi built natively from source (Tycho/Maven,
  `linux/gtk/aarch64`) at image build time. No QEMU/box64 at runtime — only
  used at `docker buildx build` time for cross-compilation; the running
  container is fully native on both architectures.
