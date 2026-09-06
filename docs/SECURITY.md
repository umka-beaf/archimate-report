# Security: authentication & authorization

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

---

<a id="русский"></a>
## 🇷🇺 Русский

### Сервис сам не аутентифицирует посетителей

`archi-report` не реализует и не будет реализовывать вход/авторизацию для
просмотра отчёта — ни в одиночном режиме, ни в [multi-model](MULTI_MODEL.md).
Это осознанное решение (`CLAUDE.md` §32.7), а не недоделанная фича: у
проекта нет ни пользовательской базы, ни ролей, ни намерения их заводить —
всё, что относится к «кто вообще может это открыть», отдано внешнему слою
(reverse-proxy перед контейнером). Единственная встроенная защита — секрет
вебхука (`WEBHOOK_SECRET`/`WEBHOOK_PROVIDER`, см. [docs/WEBHOOK.md](WEBHOOK.md))
на путь `/webhook` (или `/<slug>/webhook` в multi-режиме), и то она защищает
только сам вебхук-триггер, а не просмотр отчёта.

Если отчёт вообще не должен быть публичным — не публикуйте порт контейнера
напрямую в интернет; ставьте перед ним авторизующий прокси.

### Рекомендуемая схема: Caddy/Authentik forward-auth по path

Типичный деплой (как у автора проекта) — общий Caddy с
[Authentik](https://goauthentik.io/) в роли forward-auth провайдера перед
несколькими внутренними сервисами. Для `archi-report` это удобно тем, что
путь на модель (`/<slug>/`) — естественная граница для правила: разным
стейкхолдерам можно дать доступ к разным моделям одним и тем же
Authentik-приложением/policy, ориентируясь на path, а не на отдельный
инстанс контейнера.

Пример (общий reverse-proxy Caddyfile, не тот, что внутри образа):

```caddyfile
report.example.com {
    # Всё, КРОМЕ /*/webhook — см. следующий раздел, почему это критично.
    @needs_auth not path /*/webhook
    forward_auth @needs_auth authentik:9000 {
        uri /outpost.goauthentik.io/auth/caddy
        copy_headers X-Authentik-Username X-Authentik-Groups
    }
    reverse_proxy archi-report:3000
}
```

Тот же принцип применим к любому другому forward-auth провайдеру
(Traefik+Authelia, oauth2-proxy и т.д.) — суть не меняется: правило
авторизации должно матчиться на путь модели, а не на весь хост целиком, и
обязано исключать путь вебхука.

### Критично: не заворачивайте `/<slug>/webhook` под общий auth

Правило авторизации, навешанное на весь `/<slug>/*` без исключений,
**сломает реальные вебхуки** от GitHub/GitLab — они не проходят
forward-auth (у них нет сессии/cookie вашего Authentik/Authelia), запрос до
`archi-webhook` просто не долетит, форвард-прокси отдаст 401/redirect
раньше. Вебхук-путь и так защищён собственным механизмом
(`WEBHOOK_SECRET`+HMAC/token-сравнение, см. [docs/WEBHOOK.md](WEBHOOK.md)) —
исключайте `/webhook` (одиночный режим) или `/*/webhook` (multi-режим) из
правила внешней аутентификации явно, как в примере выше. `/status`
(`/<slug>/status`) можно оставить под auth или тоже исключить — это вопрос
вкуса, не безопасности (там нет ничего чувствительнее факта, идёт ли сейчас
генерация).

### Общий `WEBHOOK_SECRET` на все модели — принятый компромисс

В multi-model режиме все модели используют один и тот же `WEBHOOK_SECRET` и
одну схему проверки (`WEBHOOK_PROVIDER`) — нет отдельного секрета на модель.
Это сознательное упрощение (`CLAUDE.md` §32.1): у сервиса один владелец,
секрет и так не раскрывается никому за пределами git-провайдера, которому
вы его сообщаете при настройке вебхука. Если разным моделям нужны разные
секреты (например, репозитории принадлежат разным командам, которые не
должны знать секрет друг друга) — это не поддерживается текущей версией;
обходной путь — отдельные инстансы контейнера с разными `WEBHOOK_SECRET` на
разные поддомены/пути внешнего прокси.

### Что НЕ считается угрозой в этой модели

- Знание пути `/<slug>/webhook` само по себе не даёт ничего сделать без
  верного `WEBHOOK_SECRET` — 401 на неверный/отсутствующий секрет, до
  `generate.sh` дело не доходит.
- Перечисление slug'ов через `/status`/заглушки невозможно намеренно (см.
  [docs/MULTI_MODEL.md](MULTI_MODEL.md#русский), разделы про `/` и корневой
  `/status`) — это защита от лёгкой утечки, а не гарантия того, что список
  моделей нельзя узнать вообще никаким способом (у оператора,
  настраивающего внешний прокси, список всё равно есть).

---

<a id="english"></a>
## 🇬🇧 English

### The service does not authenticate visitors itself

`archi-report` doesn't implement, and won't implement, login/authorization
for viewing the report — neither in single-model mode nor in
[multi-model mode](MULTI_MODEL.md). This is a deliberate decision
(`CLAUDE.md` §32.7), not an unfinished feature: the project has no user
base, no roles, and no intention of building either — everything about "who
can even open this" is delegated to an external layer (a reverse proxy in
front of the container). The only built-in protection is the webhook secret
(`WEBHOOK_SECRET`/`WEBHOOK_PROVIDER`, see [docs/WEBHOOK.md](WEBHOOK.md)) on
the `/webhook` path (or `/<slug>/webhook` in multi-model mode), and even
that only guards the webhook trigger itself, not viewing the report.

If the report must not be public at all, don't expose the container's port
directly to the internet — put an authenticating proxy in front of it.

### Recommended pattern: Caddy/Authentik forward-auth by path

A typical deployment (the project author's own setup) is a shared Caddy
instance with [Authentik](https://goauthentik.io/) as a forward-auth
provider in front of several internal services. For `archi-report` this is
convenient because a model's path (`/<slug>/`) is a natural rule boundary:
different stakeholders can be granted access to different models via the
same Authentik application/policy, keyed on path rather than on a separate
container instance.

Example (a shared front-door Caddyfile, not the one shipped inside the
image):

```caddyfile
report.example.com {
    # Everything EXCEPT /*/webhook — see the next section for why this matters.
    @needs_auth not path /*/webhook
    forward_auth @needs_auth authentik:9000 {
        uri /outpost.goauthentik.io/auth/caddy
        copy_headers X-Authentik-Username X-Authentik-Groups
    }
    reverse_proxy archi-report:3000
}
```

The same principle applies to any other forward-auth provider
(Traefik+Authelia, oauth2-proxy, etc.) — the substance doesn't change: the
auth rule must match the model's path, not the whole host, and must exclude
the webhook path.

### Critical: don't wrap `/<slug>/webhook` in the shared auth rule

An authorization rule applied to all of `/<slug>/*` with no exceptions
**will break real webhooks** from GitHub/GitLab — they don't go through
forward-auth (they have no session/cookie for your Authentik/Authelia), the
request never reaches `archi-webhook` at all; the forward proxy returns
401/redirect first. The webhook path is already protected by its own
mechanism (`WEBHOOK_SECRET` + HMAC/token comparison, see
[docs/WEBHOOK.md](WEBHOOK.md)) — explicitly exclude `/webhook`
(single-model) or `/*/webhook` (multi-model) from the external auth rule,
as in the example above. `/status` (`/<slug>/status`) can be left behind
auth or excluded too — that's a matter of taste, not security (it exposes
nothing more sensitive than whether a generation is currently running).

### A shared `WEBHOOK_SECRET` across all models — an accepted trade-off

In multi-model mode, every model uses the same `WEBHOOK_SECRET` and the
same verification scheme (`WEBHOOK_PROVIDER`) — there's no per-model
secret. This is a deliberate simplification (`CLAUDE.md` §32.1): the
service has a single owner, and the secret is never disclosed to anyone
beyond the git provider you give it to when configuring the webhook. If
different models need different secrets (e.g. repositories owned by
separate teams who shouldn't know each other's secret), that's not
supported by the current version; the workaround is separate container
instances with different `WEBHOOK_SECRET`s behind different
subdomains/paths on the external proxy.

### What's NOT considered a threat in this model

- Knowing the `/<slug>/webhook` path by itself doesn't let anyone do
  anything without the correct `WEBHOOK_SECRET` — a wrong/missing secret
  gets a 401 before `generate.sh` is ever invoked.
- Enumerating slugs via `/status`/placeholder pages is deliberately made
  hard (see [docs/MULTI_MODEL.md](MULTI_MODEL.md#english), the `/` and root
  `/status` sections) — this is protection against a casual leak, not a
  guarantee that the model list can't be discovered by any means at all
  (the operator configuring the external proxy already has the list).
