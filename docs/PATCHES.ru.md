## Патч для arm64 (`docker/patches/`)

🇷🇺 Русский · 🇬🇧 [English](PATCHES.md)

---

### Почему он нужен

Официальных сборок [Archi](https://www.archimatetool.com/) под Linux ARM64
не существует — только Linux x86_64, macOS (Intel/Apple Silicon), Windows
([archimatetool/archi.io/releases](https://github.com/archimatetool/archi.io/releases)).
Эмуляция x86_64-сборки через [box64](https://github.com/box64-proj/box64) на
реальном железе (Raspberry Pi 5) упирается в открытый, непочиненный
upstream-баг box64 на границе JVM/SWT/GTK3-обёрток
([ptitSeb/box64#2850](https://github.com/ptitSeb/box64/issues/2850)) — либо
зависает намертво (ядро OSGi не резолвится), либо падает по SIGBUS прямо на
первом вызове `gtk_entry_new()` при инициализации SWT `Display`.

Разбор апстримного `pom.xml` (Tycho `target-platform-configuration`) показал:
он явно перечисляет 4 target environment (`win32/x86_64`, `linux/gtk/x86_64`,
`macosx/cocoa/x86_64`, `macosx/cocoa/aarch64`) — но не `linux/gtk/aarch64`,
хотя SWT-фрагменты под этот таргет в p2-репозитории Eclipse уже есть (Eclipse
IDE официально даёт linux-aarch64 сборки). Archi их просто никогда не
запрашивал.

### Что делает патч

`docker/patches/archi-pom-add-linux-gtk-aarch64.patch` — аддитивный unified
diff к `pom.xml` апстрима: **добавляет** пятый `<environment>` (`linux` /
`gtk` / `aarch64`) к существующим четырём, ничего не удаляя и не переставляя.
Подтверждено на практике (Raspberry Pi 5): сборка занимает считанные минуты,
результат — настоящий нативный ARM64 ELF-бинарник (проверено байтами
`e_machine` ELF-заголовка), отчёт побайтово идентичен amd64-версии на той же
модели, никакого box64/QEMU в рантайме.

Патч — аддитивный намеренно: если когда-нибудь amd64-ветка тоже перейдёт на
сборку из исходников (например, для версии Archi без официального tgz-релиза),
тот же патч останется применимым без изменений.

### Как он используется в Dockerfile

Стадия `archi-linux-arm64` (`docker/Dockerfile`, `FROM maven:3.9-eclipse-temurin-21`):

1. Клонирует `archimatetool/archi` по тегу `release_<ARCHI_VERSION>`
   (`--depth 1`).
2. Накладывает committed-патч (`patch -p1 < ...`) — честно аддитивный шаг,
   как описано выше.
3. **Отдельным, НЕ закоммиченным шагом** (только внутри `RUN` этой стадии, не
   в самом файле патча) комментирует оставшиеся 4 `<environment>`-блока через
   `perl -0777`-однострочник — чисто трюк для скорости сборки: этому
   Docker-стейджу нужен только `linux.gtk.aarch64`-таргет, а не полный
   4-платформенный Tycho-реактор. Committed-патч от этого не страдает —
   урезание живёт только в build-контексте этой стадии.
4. `RUN --mount=type=cache,target=/root/.m2 mvn -B -P '!tests,product' clean
   verify` — BuildKit cache mount на `~/.m2`, чтобы повторные локальные
   сборки не тянули весь p2-репозиторий Eclipse заново. CI не используется
   (см. README, «Сборка и публикация образа») — сборка идёт вручную на
   машине разработчика, где BuildKit-кеш переживает между редкими
   пересборками (пересборка — событие выхода новой версии Archi, а не
   каждый git push).
5. Извлекает `Archi-linux.gtk.aarch64.zip`, ставит `+x` на бинарник.

Версия Archi зафиксирована единым build-arg `ARCHI_VERSION`, читаемым и
`archi-linux-amd64`, и `archi-linux-arm64` — обе архитектуры одной публикации
образа всегда получают одну и ту же версию Archi. Buildx резолвит
`FROM archi-linux-${TARGETARCH}` по платформе, так что amd64-сборка никогда
не платит цену Tycho, и наоборот.

### Обновление при новой версии Archi

При выходе новой версии Archi нужно перепроверить, что патч всё ещё
накладывается чисто (`patch -p1`) и что p2-репозиторий Eclipse на момент
сборки по-прежнему содержит нужные `linux.gtk.aarch64`-фрагменты — оба
условия не гарантированы апстримом на будущее, фиксируются только через
`ARCHI_VERSION` build-arg и ручную проверку перед релизом
(`docker/scripts/smoke-test.sh` не проверяет arm64-путь — см. раздел про
`docker/scripts/smoke-test.sh` в [README](../README.ru.md)).
