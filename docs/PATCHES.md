## The arm64 patch (`docker/patches/`)

🇬🇧 English · 🇷🇺 [Русский](PATCHES.ru.md)

---

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
and a manual check before release (`docker/scripts/smoke-test.sh` doesn't exercise the
arm64 path — see the "Pre-release checks" section in the
[README](../README.md)).
