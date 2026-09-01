## The arm64 patch (`docker/patches/`)

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

---

<a id="русский"></a>
## 🇷🇺 Русский

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
(`docker/smoke-test.sh` не проверяет arm64-путь — см. раздел про
`docker/smoke-test.sh` в [README](../README.md)).

---

<a id="english"></a>
## 🇬🇧 English

### Why it exists

There is no official Linux ARM64 build of [Archi](https://www.archimatetool.com/)
— only Linux x86_64, macOS (Intel/Apple Silicon), Windows
([archimatetool/archi.io/releases](https://github.com/archimatetool/archi.io/releases)).
Emulating the x86_64 build via [box64](https://github.com/box64-proj/box64)
on real hardware (a Raspberry Pi 5) runs into an open, unfixed upstream box64
bug at the JVM/SWT/GTK3 wrapper boundary
([ptitSeb/box64#2850](https://github.com/ptitSeb/box64/issues/2850)) — it
either hangs forever (the OSGi core never resolves) or crashes with SIGBUS
right on the first `gtk_entry_new()` call during SWT `Display` initialization.

Digging into upstream's `pom.xml` (Tycho `target-platform-configuration`)
showed: it explicitly lists 4 target environments (`win32/x86_64`,
`linux/gtk/x86_64`, `macosx/cocoa/x86_64`, `macosx/cocoa/aarch64`) — but not
`linux/gtk/aarch64`, even though the Eclipse p2 repository already ships SWT
fragments for that target (Eclipse IDE officially publishes linux-aarch64
builds). Archi simply never requested it.

### What the patch does

`docker/patches/archi-pom-add-linux-gtk-aarch64.patch` is an additive unified
diff against upstream's `pom.xml`: it **adds** a fifth `<environment>`
(`linux` / `gtk` / `aarch64`) alongside the existing four, removing or
reordering nothing. Confirmed on real hardware (a Raspberry Pi 5): the build
takes a few minutes, the result is a genuine native ARM64 ELF binary
(verified via the ELF header's `e_machine` bytes), the report is
byte-identical to the amd64 version on the same model, and there's no
box64/QEMU at runtime whatsoever.

The patch is deliberately additive: if the amd64 branch ever also moves to
building from source (e.g. for an Archi version with no official tgz
release), the same patch stays applicable unchanged.

### How it's used in the Dockerfile

The `archi-linux-arm64` stage (`docker/Dockerfile`,
`FROM maven:3.9-eclipse-temurin-21`):

1. Clones `archimatetool/archi` at tag `release_<ARCHI_VERSION>` (`--depth 1`).
2. Applies the committed patch (`patch -p1 < ...`) — the honestly additive
   step described above.
3. **In a separate, NOT committed step** (only inside this stage's `RUN`, not
   in the patch file itself), comments out the remaining 4 `<environment>`
   blocks via a `perl -0777` one-liner — a pure build-speed trick: this
   Docker stage only ever needs the `linux.gtk.aarch64` target, not a full
   4-platform Tycho reactor. The committed patch is unaffected — the
   trimming only lives inside this stage's build context.
4. `RUN --mount=type=cache,target=/root/.m2 mvn -B -P '!tests,product' clean
   verify` — a BuildKit cache mount on `~/.m2` so repeated local builds don't
   re-download the entire Eclipse p2 repository every time. No CI is used
   (see the README's "Building and publishing the image" section) —
   publishing is manual, on the developer's own machine, where the BuildKit
   cache survives between the infrequent rebuilds (a rebuild happens when a
   new Archi version ships, not on every git push).
5. Extracts `Archi-linux.gtk.aarch64.zip`, marks the binary executable.

The Archi version is pinned via a single `ARCHI_VERSION` build-arg, read by
both `archi-linux-amd64` and `archi-linux-arm64` — both architectures of a
given image publish always get the same Archi version. Buildx resolves
`FROM archi-linux-${TARGETARCH}` per platform, so the amd64 build never pays
the Tycho cost, and vice versa.

### Updating for a new Archi version

When a new Archi version ships, re-verify that the patch still applies
cleanly (`patch -p1`) and that the Eclipse p2 repository at build time still
carries the needed `linux.gtk.aarch64` fragments — neither is guaranteed by
upstream going forward; both are only pinned via the `ARCHI_VERSION` build-arg
and a manual check before release (`docker/smoke-test.sh` doesn't exercise the
arm64 path — see the "Pre-release checks" section in the
[README](../README.md)).
