## Webhook listener (`docker/webhook`)

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

---

## Русский

Отдельный Go-бинарник (`docker/webhook/main.go`, только stdlib, без внешних
зависимостей), собираемый в свою стадию образа (`webhook-builder`) и
запускаемый в контейнере как `archi-webhook`. Слушает **только**
`127.0.0.1:8088` — снаружи недоступен вообще, единственный публичный порт
держит Caddy, который проксирует на него `/webhook` и `/status` (см.
[docs/CADDY.md](CADDY.md)).

### Зачем отдельный процесс, а не встроенная логика в generate.sh

`archi-webhook` не дублирует git/Archi-логику — по успешной проверке подписи
он просто запускает `/usr/local/bin/generate.sh` как subprocess,
переиспользуя то же окружение контейнера (`GIT_*`/`MODEL_*`/пр., заданные
один раз через `docker run -e`). Разделение на два процесса даёт: (а)
`entrypoint.sh` может держать их оба под единым fail-fast (`wait -n` — падение
любого убивает контейнер целиком, см. README и `docker/entrypoint.sh`); (б)
HTTP-обработка (проверка подписи, дебаунс, JSON-статус) не завязана на bash.

### Три схемы проверки (`WEBHOOK_PROVIDER`)

Выбирается явно, а не автоопределяется по заголовкам — если `WEBHOOK_SECRET`
задан, а `WEBHOOK_PROVIDER` не задан или не входит в `github`/`gitlab`/
`generic`, контейнер падает при старте с понятной ошибкой (fail-fast вместо
тихо-небезопасного вебхука).

| `WEBHOOK_PROVIDER` | Функция в коде | Как проверяется |
|---|---|---|
| `github` | `verifyGitHub()` | HMAC-SHA256 тела запроса с `WEBHOOK_SECRET` как ключом, сравнение с `X-Hub-Signature-256: sha256=<hex>` |
| `gitlab` | `verifyGitLab()` | Прямое constant-time сравнение `X-Gitlab-Token` с `WEBHOOK_SECRET` |
| `generic` | `verifyGeneric()` | Прямое constant-time сравнение заголовка `X-Webhook-Secret` или query-параметра `?secret=` с `WEBHOOK_SECRET` |

Все три сравнения — constant-time (`crypto/hmac.Equal`/аналог), чтобы не течь
через timing-атаку.

### Однослотовая очередь-дебаунс

`State` (мьютекс + `running`/`pending`/`lastRunAt`/`lastSuccess`/`lastError`)
реализует дебаунс без рекурсии: `trigger()` — если генерация уже идёт, просто
выставляет `pending=true` и возвращается; `runLoop()` крутится в фоне, пока
`pending` не станет `false`, гарантируя, что второй прогон стартует сразу
после первого, но никогда не параллельно с ним. Обработчик вебхука отвечает
`202 Accepted` сразу после `trigger()`, не дожидаясь конца генерации.

### `GET /status`

Всегда отвечает (не требует секрета), JSON:

```json
{"generating": false, "last_run_at": "2026-08-19T16:22:44Z", "last_success": true, "last_error": ""}
```

`last_run_at` — `null`, пока не завершится хотя бы один прогон
(стартовая генерация запускается из `entrypoint.sh`, а не из
`archi-webhook`, — см. ниже). Используется как HEALTHCHECK-проверка образа
(любой 200 достаточен — тело не парсится, см. `docker/Dockerfile`).

`last_error` — не голая Go-ошибка (`exit status 1`), а последняя непустая
строка stderr `generate.sh` (обрезка до 300 символов), обычно ровно та,
что печатает `die()`/явный `ERROR: ...` перед выходом — этого достаточно,
чтобы понять причину падения без обращения к `docker logs`.

### Известное ограничение

`/status` не отражает самую первую (стартовую, инициированную
`entrypoint.sh`) генерацию — `State` наполняется только внутри
`runGenerateOnce()`, вызываемой из вебхук-обработчика. Сразу после успешного
старта контейнера `/status` может показывать нулевые значения, пока не
пройдёт хотя бы один вебхук-триггер. Некритично: HEALTHCHECK проверяет сам
факт ответа, а падение стартовой генерации убивает контейнер целиком (см.
README, «Проверка при падении генерации» ниже), так что пустые поля не
маскируют реальную проблему.

### Настройка

`WEBHOOK_PATH` (по умолчанию `/webhook`) регистрируется как HTTP-хендлер
только если `WEBHOOK_SECRET` задан — без секрета запрос на этот путь отдаёт
404, как будто эндпоинта нет вовсе (безопасный дефолт). Примеры настройки
GitHub/GitLab — см. [README](../README.md#вебхук).

---

## English

A standalone Go binary (`docker/webhook/main.go`, stdlib only, no external
dependencies), built in its own image stage (`webhook-builder`) and run in
the container as `archi-webhook`. It listens on `127.0.0.1:8088`
**only** — never reachable from outside the container; Caddy is the sole
public-facing process, proxying `/webhook` and `/status` to it (see
[docs/CADDY.md](CADDY.md)).

### Why a separate process instead of logic baked into generate.sh

`archi-webhook` doesn't duplicate the git/Archi logic — on a successfully
verified request it just runs `/usr/local/bin/generate.sh` as a subprocess,
reusing the same container environment (`GIT_*`/`MODEL_*`/etc., set once via
`docker run -e`). Splitting this into two processes gives: (a)
`entrypoint.sh` can keep both under one fail-fast umbrella (`wait -n` — either
one exiting kills the whole container, see the README and
`docker/entrypoint.sh`); (b) HTTP handling (signature verification, debounce,
JSON status) isn't tied to bash.

### Three verification schemes (`WEBHOOK_PROVIDER`)

Chosen explicitly, not auto-detected from headers — if `WEBHOOK_SECRET` is
set but `WEBHOOK_PROVIDER` is missing or isn't one of `github`/`gitlab`/
`generic`, the container fails at startup with a clear error (fail-fast
instead of a silently insecure webhook).

| `WEBHOOK_PROVIDER` | Code | Verification |
|---|---|---|
| `github` | `verifyGitHub()` | HMAC-SHA256 of the request body keyed with `WEBHOOK_SECRET`, compared against `X-Hub-Signature-256: sha256=<hex>` |
| `gitlab` | `verifyGitLab()` | Direct constant-time comparison of `X-Gitlab-Token` with `WEBHOOK_SECRET` |
| `generic` | `verifyGeneric()` | Direct constant-time comparison of the `X-Webhook-Secret` header or `?secret=` query parameter with `WEBHOOK_SECRET` |

All three comparisons are constant-time to avoid leaking anything via a
timing side channel.

### Single-slot debounce queue

`State` (a mutex plus `running`/`pending`/`lastRunAt`/`lastSuccess`/
`lastError`) implements debouncing without recursion: `trigger()` — if a
generation is already running, it just sets `pending=true` and returns;
`runLoop()` keeps looping in the background until `pending` is `false`,
guaranteeing a second run starts right after the first but never in parallel
with it. The webhook handler replies `202 Accepted` immediately after
`trigger()`, without waiting for the generation to finish.

### `GET /status`

Always responds (no secret required), JSON:

```json
{"generating": false, "last_run_at": "2026-08-19T16:22:44Z", "last_success": true, "last_error": ""}
```

`last_run_at` is `null` until at least one run has completed (the startup
generation is kicked off from `entrypoint.sh`, not from `archi-webhook` —
see below). Used as the image's HEALTHCHECK (any 200 is enough — the body
isn't parsed, see `docker/Dockerfile`).

`last_error` isn't a bare Go error (`exit status 1`) — it's the last
non-empty line of `generate.sh`'s stderr (truncated to 300 characters),
usually exactly what `die()`/an explicit `ERROR: ...` prints right before
exiting — enough to diagnose a failure without going to `docker logs`.

### Known limitation

`/status` doesn't reflect the very first (startup, `entrypoint.sh`-initiated)
generation — `State` is only populated inside `runGenerateOnce()`, called
from the webhook handler. Right after a successful container start, `/status`
may still show zeroed-out fields until at least one webhook trigger has run.
Not considered a problem in practice: the HEALTHCHECK only checks that
`/status` responds at all, and a failed startup generation kills the whole
container (see the README's failure-recovery notes below), so empty fields
here never mask a real issue.

### Configuration

`WEBHOOK_PATH` (default `/webhook`) is only registered as an HTTP handler if
`WEBHOOK_SECRET` is set — without a secret, requests to that path get a 404,
as if the endpoint didn't exist at all (a safe default). For GitHub/GitLab
setup examples, see the [README](../README.md#webhook).
