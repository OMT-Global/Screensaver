# Flapline

**A split-flap screensaver with somewhere to be.**

Flapline brings the soft shuffle of old airport and train-station departure
boards to your Mac. It flips, drifts, clicks through messages, shows the time
or date, and then gets out of the way when the screen saver is not running.

Built in Swift with macOS `ScreenSaver`, Core Animation, and a small affection
for mechanical things that do one job beautifully.

[![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift)](https://www.swift.org/)
![Platform](https://img.shields.io/badge/macOS-screensaver-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## What It Does

- **Custom messages**: add one phrase per line and let the board rotate through them.
- **Clock and date modes**: run it like a quiet desk clock or a calendar board.
- **Unicode support**: accents, symbols, and emoji can ride along with the classic flap alphabet.
- **Themes**: classic amber, terminal green, monochrome, and room for more.
- **Idle-friendly animation**: Core Animation drives the flip work, and the display clock stops when the saver is not visible.
- **Private by default**: configuration stays on your Mac. No account, no network service, no telemetry.

## Download

Public releases will live on GitHub Releases and at **https://flapline.app**.

Until the first signed release is published, build from source:

```bash
make install
```

That builds a Release copy and installs it into:

```text
~/Library/Screen Savers/Flapline.saver
```

## Configure

Open **System Settings -> Screen Saver**, choose **Flapline**, then open
**Options**.

The options sheet lets you tune:

- Display mode: random board, custom messages, clock, or date
- Messages: one message per line
- Message order: sequential or random
- Wave interval: how often the board updates
- Idle shuffle: whether panels drift between coordinated waves
- Board rows: approximate display density
- Theme: classic amber, terminal green, or monochrome

The original split-flap alphabet still animates through a mechanical forward
drum sequence. Other Unicode grapheme clusters render directly as valid panel
targets.

## Build

Requirements:

- macOS 12 or later
- Xcode 14 or later

Make targets:

```bash
make build         # Release build
make debug         # Debug build
make install       # Build and install to ~/Library/Screen Savers/
make install-debug # Debug install
make uninstall     # Remove the installed saver
make preview       # Open the Screen Saver settings pane
```

Xcode:

1. Open `SplitFlap.xcodeproj`.
2. Select the `SplitFlap` scheme.
3. Build.
4. Copy `Flapline.saver` from the build products into `~/Library/Screen Savers/`.

## Website

The public site is intentionally small and static:

```text
website/
```

It is configured for the single canonical domain:

```text
flapline.app
```

No `www` site is planned.

## Release Notes For Humans

For public distribution, Flapline should be Developer ID signed and notarized
before release. Unsigned local builds are fine for development, but public
downloads should avoid scary Gatekeeper warnings.

See [docs/release/public-launch.md](docs/release/public-launch.md) for the
domain, signing, website, and release checklist.

## Project Structure

| Path | Purpose |
|---|---|
| `SplitFlap/` | Screensaver source code |
| `SplitFlap/Info.plist` | Bundle metadata and principal class |
| `SplitFlap.xcodeproj` | Xcode project |
| `website/` | Static public website for `flapline.app` |
| `scripts/ci/` | Fast, extended, and release validation scripts |
| `docs/release/` | Public launch and release guidance |

## Part Of OMT Global

Flapline is a small OMT Global project: a father-and-son open-source build with
an unnecessary amount of care put into tiny moving panels.
