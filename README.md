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
| `GIT_SSH_PRIVATE_KEY` | нет* | приватный SSH-ключ (PEM или base64) |
| `GIT_SSH_KNOWN_HOSTS` | нет | содержимое known_hosts; без него — TOFU (`accept-new`) |
| `WEBHOOK_SECRET` | нет | если задан — включает `/webhook` |
| `WEBHOOK_PROVIDER` | нет** | `github` / `gitlab` / `generic` — обязателен, если задан `WEBHOOK_SECRET` |
| `WEBHOOK_PATH` | нет | путь эндпоинта, по умолчанию `/webhook` |
| `PORT` | нет | порт раздачи, по умолчанию `3000` |
| `REGENERATE_ON_START` | нет | `true` (по умолчанию) / `false` |
| `GENERATION_TIMEOUT` | нет | таймаут одного прогона генерации, сек (по умолчанию `600`) |
| `TZ` | нет | таймзона контейнера |

`*` — ровно один способ авторизации git (или ни одного — для публичных
репозиториев). `**` — обязательна только вместе с `WEBHOOK_SECRET`.

`GET /status` (тот же порт, что и отчёт) отдаёт JSON
`{generating, last_run_at, last_success, last_error}` — используется
Docker-контейнером как healthcheck.

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
