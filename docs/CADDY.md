## Caddy setup

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

---

<a id="русский"></a>
## 🇷🇺 Русский

У archimate-report один-единственный публично видимый процесс —
[Caddy](https://caddyserver.com/), слушающий `$PORT` (по умолчанию `3000`).
Всё остальное внутри контейнера — генерация отчёта, вебхук-listener —
внутреннее.

### Что делает Caddy

`docker/Caddyfile` (вшит в образ, не редактируется в рантайме):

```caddyfile
:{$PORT} {
	handle {$WEBHOOK_PATH:/webhook}* {
		reverse_proxy 127.0.0.1:8088
	}
	handle /status {
		reverse_proxy 127.0.0.1:8088
	}
	handle {
		root * /data/report
		file_server
	}
	encode gzip
}
```

- `handle {$WEBHOOK_PATH:/webhook}*` и `handle /status` проксируют на Go-вебхук
  listener (`archi-webhook`, подробнее — [docs/WEBHOOK.md](WEBHOOK.md)),
  который слушает **только** `127.0.0.1:8088` — напрямую он никогда не
  доступен, только через этот прокси. Если `WEBHOOK_SECRET` не задан, сам
  listener отдаёт 404 на путь вебхука (см. [README](../README.md#вебхук)) —
  конфиг Caddy в обоих случаях один и тот же.
- Всё остальное падает на `file_server` для `/data/report` — директории,
  содержимое которой [generate.sh](../docker/generate.sh) подменяет после
  каждой генерации.
- `encode gzip` сжимает статику на выходе — отчёт генерируется заново каждый
  раз, никаких сохранённых сжатых версий на диске нет.

### Чего Caddy сознательно не делает

- **Нет TLS-терминации.** `auto_https off`, обычный HTTP на `$PORT`. Образ
  рассчитан на то, что перед ним стоит собственный reverse-proxy (другой
  Caddy, Traefik, nginx, облачный балансировщик), если нужен HTTPS — см.
  пример `docker-compose.yml` в [README](../README.md#docker-compose)
  (только в русской секции, дублировать пример в английской не стали) —
  он как раз рассчитан на такую схему (внешняя сеть `common`, без
  опубликованных `ports:`).
- **Нет лог-файлов.** `log { output stdout; format console }` на глобальном
  уровне и никакой `log`-директивы внутри блока сайта — всё уходит в
  `docker logs`, ничего не пишется на диск в `/data` или куда-либо ещё. Нет
  лог-файла, который нужно ротировать или который мог бы неограниченно расти.
- **Нет admin API.** `admin off` — конфиг статичен на весь жизненный цикл
  контейнера, нет поверхности для рантайм-реконфигурации, которую нужно было
  бы защищать.

### Почему валидация перед публикацией тут важна

`file_server` читает `/data/report` прямо с диска на каждый запрос — никакого
in-memory кеша, который нужно было бы инвалидировать. Если бы регенерация
(по вебхуку или иначе) подменяла файлы на месте, пока Caddy их отдаёт, запрос
мог бы поймать наполовину записанный отчёт. `generate.sh` избегает этого,
генерируя во временную директорию и валидируя её (непустой `index.html` — см.
[archi#980](https://github.com/archimatetool/archi/issues/980)) до того, как
подменить содержимое `/data/report`. Сама подмена — не единый атомарный
`rename(2)` (это ломается, если `/data/report` смонтирован как том), а
быстрая последовательность `mv` — см. раздел «Тома» в
[README](../README.md#тома) и комментарий в самом
[`generate.sh`](../docker/generate.sh) про этот компромисс.

---

<a id="english"></a>
## 🇬🇧 English

archimate-report has a single public-facing process: [Caddy](https://caddyserver.com/),
listening on `$PORT` (default `3000`). Everything else in the container —
report generation, the webhook listener — is internal.

### What Caddy does

`docker/Caddyfile` (baked into the image, not user-editable at runtime):

```caddyfile
:{$PORT} {
	handle {$WEBHOOK_PATH:/webhook}* {
		reverse_proxy 127.0.0.1:8088
	}
	handle /status {
		reverse_proxy 127.0.0.1:8088
	}
	handle {
		root * /data/report
		file_server
	}
	encode gzip
}
```

- `handle {$WEBHOOK_PATH:/webhook}*` and `handle /status` proxy to the Go
  webhook listener (`archi-webhook`, see [docs/WEBHOOK.md](WEBHOOK.md) for
  details), which binds **only** to `127.0.0.1:8088` — it's never reachable
  directly, only through this proxy. If `WEBHOOK_SECRET` isn't set, the
  listener itself answers 404 on the webhook path (see
  [README](../README.md#webhook)) — Caddy's config doesn't change either
  way.
- Everything else falls through to `file_server` on `/data/report` — the
  directory whose contents [generate.sh](../docker/generate.sh) replaces
  after every generation.
- `encode gzip` compresses the static HTML/CSS/JS on the way out — the report
  is generated fresh with no persistent compressed variants on disk.

### What Caddy deliberately doesn't do

- **No TLS termination.** `auto_https off`, plain HTTP on `$PORT`. This
  image is meant to sit behind your own reverse proxy (another Caddy
  instance, Traefik, nginx, a cloud load balancer) if you need HTTPS — see
  the `docker-compose.yml` example in the [README](../README.md#docker-compose)
  (Russian section — the example itself isn't duplicated in English), which
  assumes exactly that setup (external `common` network, no published
  `ports:`).
- **No log files.** `log { output stdout; format console }` at the global
  level, and no `log` directive at all inside the site block — everything
  goes to `docker logs`, nothing is ever written to `/data` or anywhere else
  on disk. There's no log file to rotate or grow unbounded.
- **No admin API.** `admin off` — the config is static for the container's
  lifetime, there's no runtime reconfiguration surface to expose or secure.

### Why validating before publishing matters here

`file_server` reads `/data/report` directly off disk on every request — there's
no in-memory cache to invalidate. If a regeneration (webhook-triggered or
otherwise) replaced files in place while Caddy was serving them, a request
could race a half-written report. `generate.sh` avoids this by generating
into a temporary directory and validating it (non-empty `index.html` — see
[archi#980](https://github.com/archimatetool/archi/issues/980)) before
replacing the contents of `/data/report`. That swap itself isn't a single
atomic `rename(2)` (that breaks the moment `/data/report` is a mounted
volume) — just a fast sequence of `mv`s — see the "Volumes" section in the
[README](../README.md#volumes) and the comment in
[`generate.sh`](../docker/generate.sh) itself for that trade-off.
