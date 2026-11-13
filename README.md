# Naada

Naada is a small, self-contained macOS app that records the audio of one open
application — or your microphone, or both — into an MP3 file, without
interrupting or rerouting the sound you hear.

Nothing starts by itself: pick a source and a folder, then click **Record**.

![Naada window in English](docs/images/naada-en.png)

## Modes

| Mode | What is captured |
|---|---|
| Application only | The chosen application, through a private Core Audio process tap. Every other app, and the system output, is untouched. |
| Microphone only | The chosen input, or the system default input. No application audio. |
| Application and microphone | Both streams, mixed into a single MP3. |

In every mode the sound stays audible: Naada never mutes the captured
application and never changes the volume, the routing or the default output
device. Naada excludes its own audio from the capture.

## Permissions

Naada requests nothing at launch. No capture device is opened and no permission
dialog appears before you click **Record**.

- **System audio recording** — the first time you record an application, macOS
  may ask to allow it. Core Audio process taps need that authorization; the
  dialog is the audio-only one. Naada never captures images, windows or screen
  content.
- **Microphone** — requested only when a microphone is selected, and only after
  the click on **Record**. Application-only recordings never ask for it.

The app declares a single entitlement, `com.apple.security.device.audio-input`,
required for the microphone under the hardened runtime. It has no network
access, no account and no telemetry; files are written only to the folder you
choose.

## Language

English and French, selected automatically from the system language. Any other
system language falls back to English.

## Requirements

- macOS 14.2 or later (Core Audio process taps).
- Xcode, not only the command-line tools: the build compiles the Icon Composer
  icon with `xcrun actool`. Swift 5.9 or later.

## Build

```bash
git clone https://github.com/Smax2k/naada.git
cd naada
./scripts/build.sh          # produces ./Naada.app
open ./Naada.app
```

`./scripts/build.sh` assembles the bundle, compiles the icon, then signs it. It
requires the *Developer ID Application* certificate of team `BG55CF653X`; without
it the script stops with an explicit message and produces no bundle.

## Installation

Drag `Naada.app` into `/Applications`. Naada is a standard, self-contained app
bundle: no installer, no helper, no background service.

## Signature, notarization and Gatekeeper

Each build is signed **Developer ID Application** (team `BG55CF653X`) with the
hardened runtime and a secure timestamp, and its designated requirement is
pinned to the bundle identifier and the team — not to the CDHash — so rebuilding
keeps the same code requirement.

The **release DMG is notarized by Apple and carries a stapled ticket**, and so
does the `Naada.app` inside it. A copy downloaded from the internet carries the
quarantine flag, and Gatekeeper accepts it on first launch without any dialog,
even on a Mac that is offline: macOS reads the ticket from the disk image and
from the app bundle instead of asking Apple about the build.

A bundle you assemble yourself with `./scripts/build.sh` is signed the same way
but is **not notarized** — that is the local development path, and a locally
built app carries no quarantine flag, so Gatekeeper has nothing to assess.

If a copy is ever refused, the supported fix is the per-app flow: open the app
once, dismiss the dialog, then go to **System Settings → Privacy & Security**,
scroll to the Security section, click **Open Anyway** next to Naada and
authenticate. Never disable Gatekeeper system-wide, remove the quarantine
attribute, or run the app as root; if that button does not appear, rebuild the
app locally rather than weakening the system.

The notarization submissions, their identifiers and the stapling checks are
recorded in [`docs/NOTARISATION.md`](docs/NOTARISATION.md).

## Usage

1. Choose an **application**, a **microphone**, or both.
2. Choose the **output folder** (`Choose…`). The last folder is remembered.
3. Adjust the **session title** (it defaults to the application name).
4. Click **Record**, then **Stop**.

Presets keep a source, a title and a folder together for repeat sessions.

The state comes from the capture engine: `Ready`, `Preparing`, `Recording`,
`Finalizing`, `Error`. The timer runs only while capturing and freezes when you
stop.

## Output files

Name: `YYYY MM DD <session title>.mp3`

```text
2026 11 12 Meeting.mp3
2026 11 12 Meeting (2).mp3
2026 11 12 Workshop - Q&A - episode 2.mp3
```

- `/` and `:` in the title become `-`; control characters and repeated spaces
  are normalized.
- A collision adds ` (2)`, ` (3)`, and so on **before** the extension. An
  existing file is never overwritten: creation uses `O_CREAT | O_EXCL`.
- Audio is MPEG-1 Layer III, 48 kHz, stereo, 192 kbit/s, encoded by the Shine
  encoder compiled into the app.
- No ID3 tag is written: the file name carries the date and the session title.

## Tests

```bash
./scripts/test.sh     # pure unit tests, no device, no capture
./scripts/check.sh    # tests + release build + audio path, signature and icon checks
```

The tests cover file naming and collisions without overwriting, preservation of
an existing file's bytes, the simulated state machine and its frozen timer, and
encoding a synthetic PCM buffer to MP3 that is then decoded back by Core Audio —
all without any real capture. `check.sh` additionally verifies the static audio
path (no screen capture, private tap, audio authorization strings, minimum
macOS 14.2), the localization parities, the Developer ID signature and the
compiled icon; it needs the signing certificate.

## Release

```bash
./scripts/dmg.sh                # build, then write dist/Naada.dmg
./scripts/dmg.sh --no-build     # package the existing ./Naada.app
```

The disk image is named `Naada`, contains only `Naada.app` and a link to
`/Applications`, and is written to `dist/Naada.dmg`. `scripts/dmg.sh` signs the
bundle, not the disk image, and does not submit anything to Apple: notarizing
the DMG, stapling the ticket into the image and into the app, then replacing the
release asset is a separate, manual step documented in
[`docs/NOTARISATION.md`](docs/NOTARISATION.md). The DMG attached to the GitHub
release has been through it.

## Project layout

| Path | Content |
|---|---|
| `Sources/Naada` | SwiftUI app: window, capture engine, catalogues. |
| `Sources/NaadaCore` | Pure, tested logic: naming, exclusive creation, clock, MP3 writer, PCM mix. |
| `Sources/CShine` | The Shine MP3 encoder, compiled statically. |
| `Tests/NaadaCoreTests` | Unit tests, no device and no capture. |
| `packaging` | `Info.plist`, entitlements, icon, `en`/`fr` localization tables. |
| `scripts` | `build.sh`, `test.sh`, `check.sh`, `dmg.sh`, audio proof harness. |
| `docs` | Design, verification log, notarization notes. |

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — architecture, capture path, state machine, limits.
- [`docs/VERIFICATION.md`](docs/VERIFICATION.md) — what is proven, what remains unverified.
- [`docs/NOTARISATION.md`](docs/NOTARISATION.md) — notarization notes.
- [`CREDITS.md`](CREDITS.md) — MP3 encoder and license.

## Out of scope

Scheduling, audio editing, publishing, network, accounts, synchronization.
Naada records, and stops there.

## License

The Shine encoder is under the GNU LGPL-2 and is linked statically into
`Naada.app`; redistributing the bundle must follow that license — the
corresponding source is this repository. See [`CREDITS.md`](CREDITS.md).
