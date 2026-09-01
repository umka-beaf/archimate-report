<p align="center">
  <img src="assets/logo.svg" alt="archimate-report" width="480">
</p>

<p align="center">
  <b>Один <code>docker run</code> — и ваша ArchiMate-модель из git превращается в живой,<br>
  автообновляемый HTML-отчёт с RU/EN и light/dark темой.</b>
</p>

<p align="center">
  🥧 <b>Killer-фича: Archi наконец-то запускается на Raspberry Pi.</b><br>
  Никакой официальной Linux ARM64-сборки Archi не существует — мы собираем её
  <b>нативно из исходников</b>, без box64/QEMU в рантайме.<br>
  🥧 <b>Killer feature: Archi finally runs on a Raspberry Pi.</b><br>
  There's no official Linux ARM64 build of Archi — we build one <b>natively
  from source</b>, no box64/QEMU at runtime.
</p>

<p align="center">
  <a href="https://hub.docker.com/r/umkabeaf/archimate-report"><img alt="Docker Pulls" src="https://img.shields.io/docker/pulls/umkabeaf/archimate-report"></a>
  <a href="https://hub.docker.com/r/umkabeaf/archimate-report"><img alt="Docker Image Size" src="https://img.shields.io/docker/image-size/umkabeaf/archimate-report/latest"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platform-linux%2Famd64%20%7C%20linux%2Farm64-informational">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

<p align="center">🇷🇺 <a href="#russian">Русский</a> · 🇬🇧 <a href="#english">English</a></p>

---

<a id="russian"></a>
## 🇷🇺 Русский

Docker-образ, который клонирует git-репозиторий с ArchiMate-моделью
(одиночный `*.archimate` **или** [coArchi](https://www.archimatetool.com/plugins/)-репозиторий,
формат определяется автоматически), генерирует HTML-отчёт через
[Archi CLI](https://github.com/archimatetool/archi/wiki/Archi-Command-Line-Interface)
и раздаёт его статикой через [Caddy](https://caddyserver.com/). По вебхуку от
GitHub/GitLab/чего угодно — перегенерирует отчёт при пуше в репозиторий модели.

Этот README — общая точка входа в проект: он покрывает основной контракт
(env-переменные, вебхук, тома, compose) и даёт достаточно, чтобы запустить
сервис. Более глубокие темы вынесены в отдельные доки (все — двуязычные,
RU+EN):

| Документ | О чём |
|---|---|
| 🐳 [docs/CADDY.md](docs/CADDY.md) | Единственный публичный процесс: раздача отчёта + reverse proxy на вебхук, TLS-терминация снаружи, почему публикация атомарна |
| 🎨 [docs/THEMING.md](docs/THEMING.md) | RU/EN + light/dark тема отчёта (`USE_MODERN_CSS`): как устроена, как кастомизировать |
| 🪝 [docs/WEBHOOK.md](docs/WEBHOOK.md) | Go-listener `archi-webhook`: три схемы проверки подписи, однослотовый дебаунс, формат `/status` |
| 🧩 [docs/PATCHES.md](docs/PATCHES.md) | Аддитивный патч для нативной arm64-сборки Archi из исходников — зачем он и как встроен в `docker/Dockerfile` |
| 🐋 [docs/DOCKERHUB.md](docs/DOCKERHUB.md) | Короткая версия этого README для страницы образа на Docker Hub |

### ✨ Почему это может быть полезно

- **🥧 Archi на Raspberry Pi — наконец-то.** Официальной Linux ARM64-сборки
  Archi не существует, а эмуляция x86_64-версии через box64 упирается в
  открытый баг апстрима (JVM/SWT/GTK3, зависание или SIGBUS) — поэтому мы
  собираем Archi **нативно из исходников** под `linux/gtk/aarch64`
  (Tycho/Maven) прямо на этапе `docker buildx build`. Никакого QEMU/box64 в
  рантайме — на Pi 5 отчёт генерируется на «своём» железе, побайтово
  идентичный amd64-версии. Подробности — [docs/PATCHES.md](docs/PATCHES.md).
- **Формат модели определяется сам.** Одиночный `.archimate`-файл или
  coArchi-репозиторий (git-native формат модели, по файлу на элемент) — не
  нужно ничего настраивать вручную в типичном случае.
- **RU/EN + light/dark тема отчёта из коробки** (`USE_MODERN_CSS`, включена
  по умолчанию) — переключатель языка/темы прямо в отчёте, более удобные
  пропорции панелей. Хотите оригинальный вид Archi — один флаг всё выключает.
- **📝 Документация элементов рендерится как Markdown, а не сырой текст.**
  Штатный отчёт Archi просто печатает содержимое поля Documentation
  как есть — даже если вы там писали списки/таблицы/код. Здесь оно проходит
  через полноценный Markdown-рендер прямо в браузере, так что документация
  модели наконец выглядит как документация, а не как простыня текста.
  Подробности — [docs/THEMING.md](docs/THEMING.md).
- **Вебхук с дебаунсом.** `github`/`gitlab`/`generic`-подписи, однослотовая
  очередь — параллельные пуши не порождают гонку между генерациями.
- **Атомарная публикация.** Отчёт никогда не отдаётся наполовину
  сгенерированным — валидация (`index.html` не пустой, см.
  [archi#980](https://github.com/archimatetool/archi/issues/980)) и swap
  происходят до подмены содержимого раздаваемой директории.
- **Без сюрпризов на старте.** Healthcheck, таймауты и ретраи git-операций,
  понятные fail-fast ошибки конфигурации вместо тихо-неработающего сервиса.

### 🚀 Быстрый старт

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
| `GIT_SSH_PRIVATE_KEY` | нет* | приватный SSH-ключ (PEM или base64) |
| `GIT_SSH_KNOWN_HOSTS` | нет | содержимое known_hosts; без него — TOFU (`accept-new`) |
| `WEBHOOK_SECRET` | нет | если задан — включает `/webhook` |
| `WEBHOOK_PROVIDER` | нет** | `github` / `gitlab` / `generic` — обязателен, если задан `WEBHOOK_SECRET` |
| `WEBHOOK_PATH` | нет | путь эндпоинта, по умолчанию `/webhook` |
| `PORT` | нет | порт раздачи, по умолчанию `3000` |
| `REGENERATE_ON_START` | нет | `true` (по умолчанию) / `false` |
| `GENERATION_TIMEOUT` | нет | таймаут одного прогона генерации, сек (по умолчанию `600`) |
| `USE_MODERN_CSS` | нет | `true` (по умолчанию) / `false` — RU/EN + light/dark тема отчёта поверх штатного Archi-вида |
| `TZ` | нет | таймзона контейнера |

`*` — ровно один способ авторизации git (или ни одного — для публичных
репозиториев). `**` — обязательна только вместе с `WEBHOOK_SECRET`.

`GET /status` (тот же порт, что и отчёт) отдаёт JSON
`{generating, last_run_at, last_success, last_error}` — используется
Docker-контейнером как healthcheck.

### Вебхук

Без `WEBHOOK_SECRET` эндпоинт `/webhook` вообще не зарегистрирован (запрос на
него отдаёт 404) — безопасный дефолт, ничего не включается сам по себе.
Если `WEBHOOK_SECRET` задан, `WEBHOOK_PROVIDER` обязателен — контейнер
падает при старте с понятной ошибкой, если он не задан или задан неверно.

| `WEBHOOK_PROVIDER` | Как проверяется | Заголовок/параметр |
|---|---|---|
| `github` | HMAC-SHA256 тела запроса с `WEBHOOK_SECRET` в качестве ключа | `X-Hub-Signature-256: sha256=<hex>` |
| `gitlab` | Прямое constant-time сравнение с `WEBHOOK_SECRET` | `X-Gitlab-Token: <secret>` |
| `generic` | Прямое constant-time сравнение с `WEBHOOK_SECRET` | заголовок `X-Webhook-Secret: <secret>` или `?secret=<secret>` в query |

Путь эндпоинта настраивается через `WEBHOOK_PATH` (по умолчанию `/webhook`).
Успешный запрос сразу отвечает `202 Accepted` — генерация запускается
асинхронно. Прогресс/результат — через `GET /status`. Однослотовая
очередь-дебаунс: параллельные пуши не порождают гонку между двумя
одновременными `git clone`/Archi CLI.

**GitHub**: Settings → Webhooks → Add webhook — Payload URL
`https://<домен>/webhook`, Content type `application/json`, Secret =
`WEBHOOK_SECRET`, событие `push`.
**GitLab**: Settings → Webhooks — URL `https://<домен>/webhook`, Secret
token = `WEBHOOK_SECRET`, триггер `Push events`.

```bash
# ручная проверка (generic-провайдер)
curl -X POST "https://<домен>/webhook" -H "X-Webhook-Secret: change-me"
```

### Тома

Три рабочие директории, ни одна не объявлена `VOLUME` в образе — без явного
монтирования это обычные слои контейнера, не переживающие `docker rm`:

| Путь | Назначение | Монтировать? |
|---|---|---|
| `/data/report` | Готовый HTML-отчёт, который раздаёт Caddy | Да, если хотите пережить пересоздание контейнера — особенно с `REGENERATE_ON_START=false` |
| `/data/repo` | Рабочая копия git-репозитория с моделью | Опционально — ускоряет повторные запуски (`git fetch` вместо полного `clone`) |
| `/data/secrets` | Временные файлы авторизации, права `600` | Нет — создаются заново из env-переменных при каждом запуске |

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

### docker-compose

```yaml
name: archimate-report

# ── Вариативные параметры ──────────────────────
x-image:      &image      umkabeaf/archimate-report:latest
x-tz:         &tz         Europe/Moscow
x-git-url:    &git-url    https://github.com/your-org/your-model-repo.git
x-git-token:  &git-token  ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# ── Вебхук ────────────────────────────────────
x-webhook-secret:   &webhook-secret   change-me
x-webhook-provider: &webhook-provider github

# ── YAML-якоря ────────────────────────────────
x-restart: &restart
  restart: unless-stopped

x-network: &network
  networks:
    - common

services:
  archimate-report:
    <<: [*restart, *network]
    image: *image
    hostname: archimate-report
    container_name: archimate-report

    # healthcheck уже встроен в образ (см. Dockerfile HEALTHCHECK),
    # но можно переопределить/дублировать в compose для наглядности:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO /dev/null http://127.0.0.1:3000/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

    # /data/report — том, переживающий пересоздание контейнера (см. § «Тома»).
    # /data/repo не монтируем — необязательно, ускоряет только повторные fetch.
    volumes:
      - archimate-report-data:/data/report

    environment:
      TZ: *tz

      # ── Источник модели ───────────────────────
      GIT_URL: *git-url
      # GIT_REF: main
      # MODEL_PATH:                    # если авто-детект неоднозначен
      # MODEL_FORMAT: auto             # auto | plain | coarchi
      GIT_TOKEN: *git-token

      # ── Вебхук перегенерации ──────────────────
      WEBHOOK_SECRET: *webhook-secret
      WEBHOOK_PROVIDER: *webhook-provider
      # WEBHOOK_PATH: /webhook

      # ── Прочее ─────────────────────────────────
      REGENERATE_ON_START: true
      # GENERATION_TIMEOUT: 600

    # Раздаётся через общий reverse-proxy (Caddy), напрямую порт не публикуем.
    # Для локальной проверки без прокси — раскомментировать:
    # ports:
    #   - 3000:3000

networks:
  common:
    external: true
    name: common

volumes:
  archimate-report-data:
```

Сеть `common` объявлена как `external: true` — Compose её не создаёт сам, она
должна существовать заранее:

```bash
docker network create common
```

Это удобно, когда перед сервисом уже стоит общий reverse-proxy (Caddy/Traefik)
в отдельном compose-стеке. Если такого прокси нет — уберите `x-network`/
`networks` и раскомментируйте `ports: - 3000:3000`.

### 🏗️ Архитектуры

- `linux/amd64` — официальная сборка Archi (`Archi-Linux64-*.tgz`).
- `linux/arm64` — Archi собран нативно из исходников (Tycho/Maven,
  `linux/gtk/aarch64`) в момент сборки образа. Официальной Linux ARM64-сборки
  Archi не существует — Eclipse p2-репозиторий уже содержит нужные SWT/GTK
  фрагменты, апстрим их просто никогда не запрашивал. Патч, добавляющий этот
  target, аддитивный и лежит в `docker/patches/`.

### ✅ Проверка перед релизом (`docker/smoke-test.sh`)

Т.к. CI не пересобирает образ на каждый коммит (см. ниже), перед ручным
релизом стоит прогнать `docker/smoke-test.sh` — он собирает образ **только
под host-платформу** (multi-arch manifest через `--load` не собрать) и
гоняет regression-проверки логики, одинаковой на обеих архитектурах:
`generate.sh`, `entrypoint.sh`, Caddyfile, вебхук.

Проверяет: plain-формат модели (явный `MODEL_PATH`) и coArchi-формат с
автоопределением — в обоих случаях контейнер поднимается, `GET /status`
отдаёт валидный JSON, отчёт отдаётся по HTTP 200 и не пустой; плюс реальный
вебхук-раунд-трип (верный секрет → `202` → дожидаемся завершения
перегенерации; неверный секрет → `401`).

```bash
./docker/smoke-test.sh                       # build + test, ARCHI_VERSION=latest
ARCHI_VERSION=5.9.0 ./docker/smoke-test.sh    # с пином версии
SKIP_BUILD=1 IMAGE=archi-report:m5 ./docker/smoke-test.sh   # переиспользовать уже собранный образ
```

Оставляет за собой запущенные контейнеры только на время прогона — они
убираются автоматически (`trap cleanup EXIT`) независимо от исхода. Exit 0 —
можно переходить к реальной multi-arch сборке и `--push`; ненулевой код —
читать лог над упавшей проверкой и не публиковать образ.

### 📦 Сборка и публикация образа

CI не используется для автосборки на каждый коммит — публикация ручная, по
выходу новой версии Archi:

```bash
cd docker
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t umkabeaf/archimate-report:<ARCHI_VERSION> \
  -t umkabeaf/archimate-report:latest \
  --push .
```

`ARCHI_VERSION` можно передать явно через `--build-arg ARCHI_VERSION=5.9.0`,
по умолчанию резолвится `latest` через GitHub Releases API в момент сборки.

Тот же multi-arch build+push можно запустить и вручную из GitHub Actions —
см. `.github/workflows/docker-publish.yml` (`workflow_dispatch`, без
автозапуска на каждый push).

### 📄 Лицензия

[MIT](LICENSE). Сам образ включает [Archi](https://www.archimatetool.com/)
(Eclipse Public License 2.0) и плагин [coArchi](https://www.archimatetool.com/plugins/)
(собственная лицензия archimatetool.com) — они скачиваются/собираются на
этапе `docker build`, а не распространяются как часть исходников этого
репозитория.

---

<a id="english"></a>
## 🇬🇧 English

A Docker image that clones a git repository containing an ArchiMate model
(a single `*.archimate` file **or** a [coArchi](https://www.archimatetool.com/plugins/)
repository, format auto-detected), runs it through the official
[Archi CLI](https://github.com/archimatetool/archi/wiki/Archi-Command-Line-Interface)
to generate an HTML report, and serves it as static files via
[Caddy](https://caddyserver.com/). Accepts a webhook from GitHub/GitLab/anything
generic to regenerate the report on push.

This README is the project's common entry point: it covers the core contract
(env vars, webhook, volumes, compose) and gets you to a running service.
Deeper topics live in their own docs (all bilingual, RU+EN):

| Doc | What's in it |
|---|---|
| 🐳 [docs/CADDY.md](docs/CADDY.md) | The single public-facing process: serving the report + reverse proxy to the webhook, TLS termination left to you, why publishing is atomic |
| 🎨 [docs/THEMING.md](docs/THEMING.md) | The RU/EN + light/dark report theme (`USE_MODERN_CSS`): how it works, how to customize it |
| 🪝 [docs/WEBHOOK.md](docs/WEBHOOK.md) | The `archi-webhook` Go listener: the three signature-verification schemes, the single-slot debounce, the `/status` shape |
| 🧩 [docs/PATCHES.md](docs/PATCHES.md) | The additive patch behind the native arm64 Archi source build — why it exists and how it's wired into `docker/Dockerfile` |
| 🐋 [docs/DOCKERHUB.md](docs/DOCKERHUB.md) | The short version of this README, used for the Docker Hub image page |

### ✨ Why this might be useful

- **🥧 Archi on a Raspberry Pi — finally.** There's no official Linux ARM64
  build of Archi, and emulating the x86_64 build via box64 runs into an open
  upstream bug (JVM/SWT/GTK3 — hangs or SIGBUSes) — so we build Archi
  **natively from source** for `linux/gtk/aarch64` (Tycho/Maven) right at
  `docker buildx build` time. No QEMU/box64 at runtime — on a Pi 5, the
  report is generated on native silicon, byte-identical to the amd64 output.
  Details in [docs/PATCHES.md](docs/PATCHES.md).
- **Model format is auto-detected.** A single `.archimate` file or a coArchi
  repository (the git-native model format, one file per element) — no manual
  configuration needed in the common case.
- **RU/EN + light/dark report theme out of the box** (`USE_MODERN_CSS`, on by
  default) — language/theme toggle right in the report, better panel
  proportions. Prefer stock Archi styling? One flag turns it all off.
- **📝 Element documentation renders as Markdown, not raw text.** Archi's
  stock report just prints the Documentation field's contents as-is — even
  if you wrote lists/tables/code in there. Here it goes through a real
  Markdown renderer right in the browser, so your model's documentation
  finally looks like documentation instead of a wall of text. Details in
  [docs/THEMING.md](docs/THEMING.md).
- **Debounced webhook.** `github`/`gitlab`/`generic` signature schemes, a
  single-slot queue — concurrent pushes never race two generations against
  each other.
- **Atomic publishing.** The report is never served half-generated —
  validation (non-empty `index.html`, see
  [archi#980](https://github.com/archimatetool/archi/issues/980)) and the
  swap happen before the served directory's contents change.
- **No surprises at startup.** Healthcheck, git operation timeouts/retries,
  and clear fail-fast configuration errors instead of a silently broken
  service.

### 🚀 Quick start

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
| `GIT_SSH_PRIVATE_KEY` | no* | private SSH key (PEM or base64) |
| `GIT_SSH_KNOWN_HOSTS` | no | known_hosts content; without it — TOFU (`accept-new`) |
| `WEBHOOK_SECRET` | no | if set, enables `/webhook` |
| `WEBHOOK_PROVIDER` | no** | `github` / `gitlab` / `generic` — required if `WEBHOOK_SECRET` is set |
| `WEBHOOK_PATH` | no | endpoint path, defaults to `/webhook` |
| `PORT` | no | serving port, defaults to `3000` |
| `REGENERATE_ON_START` | no | `true` (default) / `false` |
| `GENERATION_TIMEOUT` | no | timeout for a single generation run, seconds (default `600`) |
| `USE_MODERN_CSS` | no | `true` (default) / `false` — RU/EN + light/dark report theme layered on Archi's stock look |
| `TZ` | no | container timezone |

`*` — exactly one git auth method (or none, for public repositories).
`**` — required only together with `WEBHOOK_SECRET`.

`GET /status` (same port as the report) returns JSON
`{generating, last_run_at, last_success, last_error}` — used as the container
healthcheck.

### Webhook

Without `WEBHOOK_SECRET`, the `/webhook` endpoint isn't registered at all
(returns 404) — a safe default, nothing is enabled implicitly. If
`WEBHOOK_SECRET` is set, `WEBHOOK_PROVIDER` is required — the container fails
at startup with a clear error if it's missing or invalid.

| `WEBHOOK_PROVIDER` | Verification | Header/parameter |
|---|---|---|
| `github` | HMAC-SHA256 of the request body, keyed with `WEBHOOK_SECRET` | `X-Hub-Signature-256: sha256=<hex>` |
| `gitlab` | Direct constant-time comparison with `WEBHOOK_SECRET` | `X-Gitlab-Token: <secret>` |
| `generic` | Direct constant-time comparison with `WEBHOOK_SECRET` | `X-Webhook-Secret: <secret>` header or `?secret=<secret>` query param |

The endpoint path is configurable via `WEBHOOK_PATH` (default `/webhook`). A
successful request immediately returns `202 Accepted` — generation runs
asynchronously. Check progress/result via `GET /status`. A single-slot
debounce queue means concurrent pushes never race two `git clone`/Archi CLI
runs against each other.

### Volumes

Three working directories; none are declared as `VOLUME` in the image —
without explicit mounting they're ordinary container layers that don't
survive `docker rm`:

| Path | Purpose | Mount it? |
|---|---|---|
| `/data/report` | Finished HTML report, served by Caddy | Yes, if you want the report to survive container recreation — especially with `REGENERATE_ON_START=false` |
| `/data/repo` | Working copy of the model's git repository | Optional — speeds up subsequent runs (`git fetch` instead of a full `clone`) |
| `/data/secrets` | Temporary auth material, `600` perms | No — recreated from env vars on every run |

### 🏗️ Architectures

- `linux/amd64` — official Archi build (`Archi-Linux64-*.tgz`).
- `linux/arm64` — Archi built natively from source (Tycho/Maven,
  `linux/gtk/aarch64`) at image build time. No official Linux ARM64 build of
  Archi exists — the Eclipse p2 repository already ships the needed SWT/GTK
  fragments, upstream just never requested that target. The additive patch
  lives in `docker/patches/`.

### ✅ Pre-release checks (`docker/smoke-test.sh`)

Since CI doesn't rebuild the image on every commit (see below), run
`docker/smoke-test.sh` before a manual release. It builds the image for the
**host platform only** (a multi-arch manifest can't be produced with
`--load`) and runs regression checks against the logic shared by both
architectures: `generate.sh`, `entrypoint.sh`, the Caddyfile, the webhook.

It checks: the plain model format (explicit `MODEL_PATH`) and the coArchi
format with auto-detection — in both cases the container comes up, `GET
/status` returns valid JSON, the report is served over HTTP 200 and isn't
empty; plus a real webhook round-trip (correct secret → `202` → wait for the
regeneration to finish; wrong secret → `401`).

```bash
./docker/smoke-test.sh                       # build + test, ARCHI_VERSION=latest
ARCHI_VERSION=5.9.0 ./docker/smoke-test.sh    # pin a version
SKIP_BUILD=1 IMAGE=archi-report:m5 ./docker/smoke-test.sh   # reuse an already-built image
```

Containers it starts only live for the duration of the run — cleaned up
automatically (`trap cleanup EXIT`) regardless of outcome. Exit 0 means it's
safe to move on to the real multi-arch build and `--push`; a non-zero exit
means read the log above the failing check and don't publish the image.

### 📦 Building and publishing the image

No CI auto-builds on every commit — publishing is manual, triggered by a new
Archi release:

```bash
cd docker
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t umkabeaf/archimate-report:<ARCHI_VERSION> \
  -t umkabeaf/archimate-report:latest \
  --push .
```

`ARCHI_VERSION` can be pinned explicitly via `--build-arg
ARCHI_VERSION=5.9.0`; it defaults to resolving `latest` via the GitHub
Releases API at build time.

The same multi-arch build+push can also be run manually from GitHub Actions
— see `.github/workflows/docker-publish.yml` (`workflow_dispatch`, no
auto-trigger on every push).

### 📄 License

[MIT](LICENSE). The image itself bundles [Archi](https://www.archimatetool.com/)
(Eclipse Public License 2.0) and the [coArchi](https://www.archimatetool.com/plugins/)
plugin (archimatetool.com's own license) — downloaded/built at `docker build`
time, not distributed as part of this repository's source.
