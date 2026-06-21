# SplitFlap

A macOS screensaver that simulates a **split-flap mechanical display** — the satisfying flip-card boards once found in airports and train stations around the world.

Built entirely in Swift using the native `ScreenSaver` framework and Core Animation.

![Language](https://img.shields.io/badge/Swift-5-orange?logo=swift) ![Platform](https://img.shields.io/badge/macOS-screensaver-blue) ![License](https://img.shields.io/badge/license-MIT-green)

---

## How it works

The display cycles through two alternating phases:

- **Idle shuffle** — individual panels drift to random characters at a natural, staggered pace
- **Wave update** — a left-to-right wave sweeps across all panels in a coordinated flip

Each character flip is animated mechanically: the top flap falls, then the new bottom flap rises, matching the physics of a real split-flap unit.

---

## Requirements

- macOS 12 or later
- Xcode 14+

---

## Build & Install

**Using Make (recommended):**

```bash
# Build and install to ~/Library/Screen Savers/
make install

# Build only (Release)
make build

# Build Debug
make debug

# Uninstall
make uninstall
```

**Using Xcode:**

1. Open `SplitFlap.xcodeproj`
2. Select the `SplitFlap` scheme
3. Build (⌘B)
4. Copy `SplitFlap.saver` from the build products to `~/Library/Screen Savers/`

---

## Activate

1. Open **System Settings → Screen Saver**
2. Select **SplitFlap** from the list

## Configure

Open the SplitFlap options sheet from System Settings to choose what the board
displays:

- **Display**: random board, custom messages, clock, or date
- **Messages**: one message per line, including Unicode text and emoji
- **Message order**: sequential or random
- **Wave interval**: how often the board updates
- **Idle shuffle**: whether panels drift between coordinated waves
- **Board rows**: approximate display density
- **Theme**: classic amber, terminal green, or monochrome

The original split-flap alphabet still animates through a mechanical forward
drum sequence. Other Unicode grapheme clusters render directly as valid panel
targets.

---

## Project structure

| File | Purpose |
|---|---|
| `SplitFlapView.swift` | Principal screensaver class, registered with macOS |
| `CharacterGrid.swift` | Manages the grid of individual panel cells |
| `CharacterSet.swift` | Defines the character alphabet and ordering |
| `SplitFlapPanel.swift` | Renders a single split-flap cell with CALayers |
| `FlipAnimator.swift` | Drives the mechanical flip animation via `CABasicAnimation` |
| `DisplayClock.swift` | Orchestrates idle and wave phases with a dispatch timer |

---

## Part of [OMT Global](https://github.com/omt-global)

A father-and-son open-source project.
