# archimate-report

Docker-образ, который клонирует git-репозиторий с ArchiMate-моделью (одиночный
`*.archimate` или coArchi-репозиторий), генерирует HTML-отчёт через
[Archi CLI](https://github.com/archimatetool/archi/wiki/Archi-Command-Line-Interface)
и раздаёт его статикой через Caddy. Поддерживает вебхук для перегенерации по
пушу. Публикуется как multi-arch (`linux/amd64` + `linux/arm64`, честная
нативная сборка на обеих архитектурах — без эмуляции, подробности в
[CLAUDE.md](CLAUDE.md) §5, §15.9–§15.10) образ:
[`umkabeaf/archimate-report`](https://hub.docker.com/r/umkabeaf/archimate-report).

## Быстрый старт

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

## Переменные окружения

Полный и всегда актуальный контракт — [CLAUDE.md](CLAUDE.md) §7. Кратко:

| Переменная | Обязательна | Описание |
|---|---|---|
| `GIT_URL` | да | URL репозитория (`https://` или `git@...`) |
| `GIT_REF` | нет | ветка/тег/коммит, по умолчанию — HEAD дефолтной ветки |
| `MODEL_PATH` | нет | путь к `.archimate`-файлу или корню coArchi-репозитория, если авто-детект неоднозначен |
| `MODEL_FORMAT` | нет | `auto` (по умолчанию) / `plain` / `coarchi` |
| `GIT_TOKEN` | нет* | HTTPS-токен (PAT) |
| `GIT_USERNAME` / `GIT_PASSWORD` | нет* | логин+пароль для HTTPS |
| `GIT_SSH_PRIVATE_KEY` | нет* | приватный SSH-ключ (PEM или base64) ⚠️ не протестировано end-to-end, будет позже (см. CLAUDE.md §18.1) |
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
`{generating, last_run_at, last_success, last_error}` — используется
Docker-контейнером как healthcheck.

## Вебхук

Без `WEBHOOK_SECRET` эндпоинт `/webhook` вообще не зарегистрирован (запрос на
него отдаёт 404) — безопасный дефолт, ничего не включается по умолчанию.
Если `WEBHOOK_SECRET` задан, `WEBHOOK_PROVIDER` обязателен — контейнер
падает при старте с понятной ошибкой, если он не задан или задан неверно.
Способ проверки подписи зависит от провайдера:

| `WEBHOOK_PROVIDER` | Как проверяется | Заголовок/параметр |
|---|---|---|
| `github` | HMAC-SHA256 тела запроса с `WEBHOOK_SECRET` в качестве ключа | `X-Hub-Signature-256: sha256=<hex>` |
| `gitlab` | Прямое constant-time сравнение с `WEBHOOK_SECRET` | `X-Gitlab-Token: <secret>` |
| `generic` | Прямое constant-time сравнение с `WEBHOOK_SECRET` | заголовок `X-Webhook-Secret: <secret>` или `?secret=<secret>` в query |

Путь эндпоинта настраивается через `WEBHOOK_PATH` (по умолчанию `/webhook`).
Успешный запрос сразу отвечает `202 Accepted` — генерация запускается
асинхронно, ответ не ждёт её завершения. Прогресс/результат смотрите через
`GET /status`.

**Настройка в GitHub**: Settings → Webhooks → Add webhook, Payload URL —
`https://<ваш-домен>/webhook`, Content type — `application/json`, Secret —
значение `WEBHOOK_SECRET`, событие — `push`.

**Настройка в GitLab**: Settings → Webhooks, URL — `https://<ваш-домен>/webhook`,
Secret token — значение `WEBHOOK_SECRET`, триггер — `Push events`.

**Ручной вызов для проверки** (`generic`-провайдер):

```bash
curl -X POST "https://<ваш-домен>/webhook" \
  -H "X-Webhook-Secret: change-me"
```

Однослотовая очередь-дебаунс: если генерация уже идёт, второй прогон не
запускается параллельно — он выполнится сразу после текущего. Параллельные
пуши не порождают гонку между двумя одновременными `git clone`/Archi CLI.

## Тома

В образе (`Dockerfile`) есть три рабочие директории. Ни одна не объявлена
инструкцией `VOLUME` — то есть без явного монтирования это обычные слои
контейнера, не переживающие `docker rm`:

| Путь | Назначение | Монтировать? |
|---|---|---|
| `/data/report` | Готовый HTML-отчёт, который раздаёт Caddy | Да, если хотите, чтобы отчёт пережил пересоздание контейнера — особенно вместе с `REGENERATE_ON_START=false`, чтобы не ждать полной регенерации при каждом рестарте |
| `/data/repo` | Рабочая копия git-репозитория с моделью | Опционально — при монтировании повторные запуски делают `git fetch` вместо полного `clone`, что быстрее на больших репозиториях |
| `/data/secrets` | Временные файлы авторизации (SSH-ключ/токен/пароль), права `600` | Не монтируйте — создаются заново из env-переменных при каждом запуске `generate.sh`; volume тут только продлевает жизнь секретов на диске без пользы |

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

## docker-compose

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
должна существовать заранее, иначе `docker compose up` упадёт с ошибкой вида
`network common declared as external, but could not be found`. Создаётся один
раз (переживает `docker compose down`/пересоздание стека):

```bash
docker network create common
```

Это удобно, когда перед сервисом уже стоит общий reverse-proxy (например,
Caddy/Traefik) в отдельном compose-стеке, подключённый к той же сети — тогда
`archimate-report` не публикует порт наружу напрямую, а достаётся прокси по
имени контейнера внутри `common`. Если такого прокси нет и сеть заводить не
хочется — просто уберите `x-network`/`networks` из примера и раскомментируйте
`ports: - 3000:3000`, тогда сервис будет доступен напрямую на хосте.

## Сборка и публикация образа

CI не используется — публикация ручная, по выходу новой версии Archi:

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

## Подробности реализации

Вся история решений, спайков и milestone-результатов — в [CLAUDE.md](CLAUDE.md).
