# Multi-model mode

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

---

<a id="русский"></a>
## 🇷🇺 Русский

Один инстанс сервиса может раздавать отчёты сразу по нескольким ArchiMate-
моделям (разные репозитории или разные модели в одном репозитории), каждая —
под своим URL-путём `/<slug>/`. Дизайн зафиксирован в `CLAUDE.md` §32,
реализация — §33 (M6.1–M6.4). Этот документ — практический контракт: как
включить режим, что при этом меняется, чего не меняется.

### Как включить

Ничего специально «включать» не нужно — режим определяется автоматически.
Если в окружении контейнера обнаружена хотя бы одна переменная
`MODEL_<N>_SLUG` (`<N>` — произвольное целое число), сервис целиком переходит
в multi-model режим. Если ни одной такой переменной нет — работает как
раньше, одиночная модель через голый `GIT_URL` (см. основной README).

`<N>` не обязано быть последовательным и не обязано начинаться с 1 — модели
можно добавлять по одной, не пересчитывая соседей: сегодня `MODEL_1_*` и
`MODEL_2_*`, через полгода добавили `MODEL_7_*`, ничего в 1 и 2 менять не
нужно.

### Переменные окружения

**На модель** (замените `<N>` на номер модели) — тот же контракт, что и у
одиночной модели, только с префиксом `MODEL_<N>_`:

| Переменная | Обязательна | Описание |
|---|---|---|
| `MODEL_<N>_SLUG` | да (маркер модели) | URL-путь модели: только ASCII-буквы, цифры, дефис (`^[A-Za-z0-9-]+$`) |
| `MODEL_<N>_GIT_URL` | да | URL репозитория |
| `MODEL_<N>_GIT_REF` | нет | ветка/тег/коммит |
| `MODEL_<N>_MODEL_PATH` | нет | путь к `.archimate`-файлу или корню coArchi-репозитория |
| `MODEL_<N>_MODEL_FORMAT` | нет | `auto` / `plain` / `coarchi` |
| `MODEL_<N>_GIT_TOKEN` | нет* | HTTPS-токен |
| `MODEL_<N>_GIT_USERNAME` / `MODEL_<N>_GIT_PASSWORD` | нет* | логин+пароль для HTTPS |
| `MODEL_<N>_GIT_SSH_PRIVATE_KEY` | нет* | приватный SSH-ключ |
| `MODEL_<N>_GIT_SSH_KNOWN_HOSTS` | нет | known_hosts для этой модели |
| `MODEL_<N>_GENERATION_TIMEOUT` | нет | таймаут генерации для этой модели, сек (по умолчанию `600`) |

`*` — ровно один способ авторизации git на модель (или ни одного — для
публичных репозиториев). Разные модели могут использовать разные способы
авторизации и разные `GIT_REF`/`MODEL_FORMAT` независимо друг от друга.

**Общие на весь инстанс** (без префикса, как и раньше) — `WEBHOOK_SECRET`,
`PORT`, `TZ`, `REGENERATE_ON_START`, `USE_MODERN_CSS`. У сервиса один
владелец, поэтому один секрет вебхука и одна тема оформления на все модели —
осознанный компромисс, а не недосмотр (per-model оверрайд для этих двух
последних не исключён на будущее, но не реализован). `WEBHOOK_PATH` в
multi-режиме не читается вовсе — путь вебхука на модель всегда
`/<slug>/webhook`, отдельно не настраивается.

Голый `GIT_URL` (без префикса) в multi-режиме **не** считается «нулевой
моделью» — он просто игнорируется, с предупреждением в лог
(`GIT_URL is set but MODEL_<N>_SLUG vars were found — ...`). Миграция с
одиночной модели на множественную — ручная: перенесите старые `GIT_*` в
`MODEL_1_*` и дайте ей `MODEL_1_SLUG`.

### Пример

```bash
docker run -d \
  --name archimate-report \
  -p 3000:3000 \
  -e MODEL_1_SLUG=archisurance \
  -e MODEL_1_GIT_URL=https://github.com/archimatetool/ArchiModels.git \
  -e MODEL_1_MODEL_PATH=Archisurance/Archisurance.archimate \
  -e MODEL_2_SLUG=glycam \
  -e MODEL_2_GIT_URL=https://github.com/GLYCAM-Web/coArchi-GLYCAM-Web.git \
  -e WEBHOOK_SECRET=change-me \
  -e WEBHOOK_PROVIDER=generic \
  umkabeaf/archimate-report:latest
```

Отчёты будут доступны на `http://localhost:3000/archisurance/` и
`http://localhost:3000/glycam/`.

### Файловая раскладка

Те же три тома, что и в одиночном режиме (см. README, «Тома»), с
подпапкой на slug внутри каждого — монтировать по-прежнему можно `/data`
целиком:

```
/data/repo/<slug>/
/data/report/<slug>/
/data/secrets/<slug>/
```

### `/` и заглушки

На `/` в multi-режиме отдаётся статическая обезличенная заглушка — она
**не перечисляет** slug'и существующих моделей: список моделей — это
потенциальная утечка информации в обход внешнего слоя авторизации, поэтому
обнаружение URL конкретной модели осознанно оставлено на совести
администратора/этого документа, а не самого сервиса (см. `CLAUDE.md` §32.4).
Та же заглушка (другой текст) отдаётся на `/<slug>/`, пока для этой модели
ещё не было ни одной успешной генерации — не голый 404, а понятное
сообщение с указанием посмотреть `docker logs`/`/<slug>/status`. Как только
появляется реальный отчёт (`index.html` в `/data/report/<slug>/`), заглушка
на него больше не накладывается — в том числе при рестарте контейнера с
персистентным volume.

Путь, не относящийся ни к одной известной модели (например,
`/nosuchmodel/`), отдаёт обычный Caddy 404 — заглушки не перехватывают
произвольные пути.

### Вебхук и `/status` на модель

Каждая обнаруженная модель получает свои `/<slug>/webhook` и
`/<slug>/status` — подробности схем проверки подписи те же, что в
[docs/WEBHOOK.md](WEBHOOK.md), просто путь несёт префикс slug'а. Корневой
`GET /status` в multi-режиме упрощён до `{"generating": bool}` — без
привязки к конкретной модели (та же логика, что и с заглушками на `/`: не
давать способ угадать/подтвердить список моделей через общий эндпоинт).
Для детального статуса конкретной модели — `GET /<slug>/status`, полный JSON
`{generating, last_run_at, last_success, last_error}`, как у одиночной
модели.

### Очередь генерации

Один общий последовательный воркер на весь контейнер, не по воркеру на
модель — генерации разных моделей никогда не выполняются параллельно.
Дебаунс — per-slug: повторный триггер для модели, уже стоящей в очереди или
уже генерирующейся, не создаёт вторую запись, просто «догоняет» после
текущего прогона. Триггер для другой модели в это время не блокируется —
он встаёт в ту же очередь и обрабатывается по порядку. Пример: три вебхука
подряд (модель A, модель B, снова модель A) дадут строго последовательный
порядок обработки `A → B → A`, без параллельного выполнения и без потери
последнего триггера A.

При старте контейнера (`REGENERATE_ON_START=true`, по умолчанию) все
обнаруженные модели ставятся в ту же очередь в порядке возрастания `<N>` —
на инстансе с 20+ моделями суммарный старт может занять заметное время,
это принятый компромисс (см. `CLAUDE.md` §32.5), отдельного флага
«не генерировать эту модель при старте» нет.

### Обработка ошибок при старте

В отличие от одиночного режима (где падение стартовой генерации убивает
весь контейнер — отдавать всё равно нечего), в multi-режиме падение
генерации одной модели при старте **не** останавливает контейнер целиком —
логируется предупреждение именно по этой модели, остальные поднимаются и
публикуются как обычно. Для уже когда-то успешно сгенерированной модели,
упавшей на последующем вебхук-триггере, поведение то же, что и в одиночном
режиме — старый валидный отчёт остаётся на месте (см. README, раздел про
защиту отчёта при падении регенерации).

### Аутентификация

Сервис не реализует аутентификацию сам ни в одном режиме — см.
[docs/SECURITY.md](SECURITY.md), особенно раздел про то, как не сломать
реальные вебхуки правилом внешнего прокси, навешанным на весь `/<slug>/*`.

---

<a id="english"></a>
## 🇬🇧 English

A single service instance can serve reports for several ArchiMate models at
once (different repositories, or different models within one repository),
each under its own URL path `/<slug>/`. The design is recorded in
`CLAUDE.md` §32, the implementation in §33 (M6.1–M6.4). This document is the
practical contract: how to turn it on, what changes, what doesn't.

### How to enable it

There's no explicit switch — the mode is auto-detected. If the container's
environment has at least one `MODEL_<N>_SLUG` variable (`<N>` any integer),
the service runs entirely in multi-model mode. If none is present, it works
exactly as before — a single model via a bare `GIT_URL` (see the main
README).

`<N>` doesn't need to be sequential or start at 1 — models can be added one
at a time without renumbering neighbors: `MODEL_1_*`/`MODEL_2_*` today,
`MODEL_7_*` added six months later, nothing about 1 or 2 needs to change.

### Environment variables

**Per model** (replace `<N>` with the model's number) — the same contract as
a single model, just prefixed with `MODEL_<N>_`:

| Variable | Required | Description |
|---|---|---|
| `MODEL_<N>_SLUG` | yes (marks the model) | URL path segment: ASCII letters/digits/hyphens only (`^[A-Za-z0-9-]+$`) |
| `MODEL_<N>_GIT_URL` | yes | Repository URL |
| `MODEL_<N>_GIT_REF` | no | branch/tag/commit |
| `MODEL_<N>_MODEL_PATH` | no | path to the `.archimate` file or coArchi repo root |
| `MODEL_<N>_MODEL_FORMAT` | no | `auto` / `plain` / `coarchi` |
| `MODEL_<N>_GIT_TOKEN` | no* | HTTPS token |
| `MODEL_<N>_GIT_USERNAME` / `MODEL_<N>_GIT_PASSWORD` | no* | login+password for HTTPS |
| `MODEL_<N>_GIT_SSH_PRIVATE_KEY` | no* | private SSH key |
| `MODEL_<N>_GIT_SSH_KNOWN_HOSTS` | no | known_hosts for this model |
| `MODEL_<N>_GENERATION_TIMEOUT` | no | generation timeout for this model, seconds (default `600`) |

`*` — exactly one git auth method per model (or none, for public
repositories). Different models can use different auth methods and
different `GIT_REF`/`MODEL_FORMAT` independently of each other.

**Instance-wide** (unprefixed, as before) — `WEBHOOK_SECRET`, `PORT`, `TZ`,
`REGENERATE_ON_START`, `USE_MODERN_CSS`. The service has a single owner, so
one webhook secret and one theme apply to all models — a deliberate
trade-off, not an oversight (a future per-model override for the latter two
isn't ruled out, but isn't implemented). `WEBHOOK_PATH` isn't consulted at
all in multi-model mode — a model's webhook path is always
`/<slug>/webhook`, not separately configurable.

A bare `GIT_URL` (unprefixed) in multi-model mode is **not** treated as a
"model zero" — it's simply ignored, with a warning logged
(`GIT_URL is set but MODEL_<N>_SLUG vars were found — ...`). Migrating from
a single model to multiple is manual: move the old `GIT_*` vars into
`MODEL_1_*` and give it a `MODEL_1_SLUG`.

### Example

```bash
docker run -d \
  --name archimate-report \
  -p 3000:3000 \
  -e MODEL_1_SLUG=archisurance \
  -e MODEL_1_GIT_URL=https://github.com/archimatetool/ArchiModels.git \
  -e MODEL_1_MODEL_PATH=Archisurance/Archisurance.archimate \
  -e MODEL_2_SLUG=glycam \
  -e MODEL_2_GIT_URL=https://github.com/GLYCAM-Web/coArchi-GLYCAM-Web.git \
  -e WEBHOOK_SECRET=change-me \
  -e WEBHOOK_PROVIDER=generic \
  umkabeaf/archimate-report:latest
```

Reports will be available at `http://localhost:3000/archisurance/` and
`http://localhost:3000/glycam/`.

### File layout

The same three volumes as single-model mode (see the README's "Volumes"
section), each with a slug subdirectory — mounting `/data` as a whole still
works:

```
/data/repo/<slug>/
/data/report/<slug>/
/data/secrets/<slug>/
```

### `/` and placeholder pages

In multi-model mode, `/` serves a static, deliberately anonymous placeholder
page — it **doesn't list** the configured slugs: the model list is a
potential information leak around an external auth layer, so discovering a
given model's URL is left to the administrator/this document, not the
service itself (see `CLAUDE.md` §32.4). The same placeholder mechanism
(different text) is served at `/<slug>/` until that model has had at least
one successful generation — not a bare 404, but a clear message pointing at
`docker logs`/`/<slug>/status`. Once a real report exists
(`index.html` under `/data/report/<slug>/`), the placeholder no longer
overwrites it — including across a container restart with a persistent
volume.

A path that doesn't match any known model (e.g. `/nosuchmodel/`) gets a
plain Caddy 404 — the placeholders don't intercept arbitrary paths.

### Per-model webhook and `/status`

Every discovered model gets its own `/<slug>/webhook` and `/<slug>/status`
— the verification schemes are the same as documented in
[docs/WEBHOOK.md](WEBHOOK.md), just with the slug as a path prefix. The root
`GET /status` is simplified to `{"generating": bool}` in multi-model mode —
not tied to any specific model (same rationale as the `/` placeholder: don't
give a way to guess/confirm the model list via a shared endpoint). For a
given model's detailed status, use `GET /<slug>/status`, the full JSON
`{generating, last_run_at, last_success, last_error}`, same shape as
single-model mode.

### Generation queue

One shared sequential worker for the whole container, not one per model —
different models' generations never run in parallel. Debouncing is
per-slug: a repeated trigger for a model that's already queued or already
running doesn't add a second entry, it just "catches up" after the current
run finishes. A trigger for a different model isn't blocked meanwhile — it
joins the same queue and is processed in turn. Example: three webhooks in a
row (model A, model B, model A again) produce a strictly sequential
`A → B → A` processing order, never in parallel, and the last A trigger is
never dropped.

On container start (`REGENERATE_ON_START=true`, the default), every
discovered model is queued in ascending `<N>` order — on an instance with
20+ models, the combined startup time can be noticeable; this is an
accepted trade-off (see `CLAUDE.md` §32.5), there's no "skip this model at
startup" flag.

### Startup failure handling

Unlike single-model mode (where a failed startup generation kills the whole
container — there's nothing else to serve anyway), in multi-model mode one
model failing to generate at startup does **not** stop the container — a
warning is logged for that model specifically, the rest still come up and
publish normally. For a model that has generated successfully before and
fails on a later webhook trigger, behavior matches single-model mode — the
previous valid report stays in place (see the README's notes on protecting
the report across a failed regeneration).

### Authentication

The service doesn't implement authentication itself in either mode — see
[docs/SECURITY.md](SECURITY.md), especially the section on not breaking
real webhooks with an external proxy rule applied to all of `/<slug>/*`.
