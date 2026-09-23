[English](README.md) | [简体中文](README.zh-CN.md)
# iCube

An iOS speedcubing practice app built with SwiftUI and RealityKit. It supports 2x2 / 3x3 / 4x4 cubes, multiple paint skins, gesture-based turning, speed timing with statistics, and an interactive illustrated tutorial with 3D demonstrations.

## Features

### Practice

- **Multiple cube sizes**: full feature parity across 2x2, 3x3, and 4x4 — gestures, scrambles, timing, solve detection, and record keeping, with a global size switch
- **WCA-style scrambles**: random scrambles aligned with official rules (11 moves for 2x2, 20 for 3x3, 40 for 4x4; 4x4 includes inner-layer turns such as 2R), replayed step by step with animation
- **Speed timing**: stack-mate style flow — hold to ready, release to start the timer; +2 / DNF penalties supported
- **Statistics**: best time, WCA-style averages (ao5 / ao12), and history filterable by cube size

### Gestures

- **Touch to turn**: touch a sticker and slide to turn the corresponding layer; multiple fingers can turn unrelated layers simultaneously
- **Orbit**: drag outside the cube silhouette to rotate the view; arbitration between the two is resolved by raycast hit results
- **Pinch to zoom**: two-finger pinch on empty space scales the cube (clamped to 0.7x–1.5x)

### Skins

- 5 built-in skins: Classic, Race, Frost, Candy, and Obsidian (color palettes inspired by popular cube brands, with independently adjusted values and materials)
- Instant global switching without rebuilding the scene; the selection is persisted

### Tutorial

- CFOP-adjacent beginner method (7 stages) plus 2-look OLL / PLL, covering 8 stages and 20+ cases
- Each case ships with a 3D demonstration: the cube is automatically set to the case pattern, then the algorithm is played step by step until solved
- Every case is verified by unit tests (case = solved state + inverse of the algorithm, so playing the algorithm always solves it)
- The demonstration model follows the global cube size and current skin

### Restore assistant

- **Manual entry**: paint the standard unfolded net cell by cell — tap or drag to brush continuously. The six centers come pre-filled with the standard color scheme, so only 48 cells are left
- **Live validation**: cell count and per-color counts are reported as you go; solving unlocks only once the net is full and balanced
- **Short solutions**: Kociemba two-phase algorithm — typically 20–24 moves for a random scramble, roughly 26 ms per solve
- **Text + animated steps**: a numbered step strip highlights and auto-scrolls as the animation plays, with replay, reset, and three speed settings
- Illegal states (a single flipped edge, a single twisted corner, a parity error) are rejected by the solver with a plain-language explanation

## Tech Stack & Architecture

| Layer | Technology |
|-------|------------|
| UI | SwiftUI (iOS 18+) |
| 3D rendering | RealityKit (`RealityView` + camera content) |
| Persistence | SwiftData (solve records), UserDefaults (skin / size preferences) |
| Core algorithms | CubeKit (local SwiftPM package) |
| Cube solving | CubeSolve (local SwiftPM package) + vendored [SwiftTB2PKit](https://github.com/edmw/SwiftTB2PKit) |

### CubeKit design

CubeKit is a pure Swift algorithm package, fully decoupled from the app layer with no UIKit / RealityKit dependencies:

- **Geometry-derived correctness**: every turn permutation is derived at runtime by rotating integer lattice coordinates 90° about an axis — no hand-copied lookup tables anywhere; correctness is guaranteed by geometric invariants
- **N×N generalization**: state, layer membership, notation (including `2R` inner-layer and `Rw` wide moves), and scrambles are all parameterized by cube size; the size is inferred from the sticker count (6N²), keeping the data model backward compatible
- **Deterministic scrambles**: seedable SplitMix64 randomness — the same seed reproduces the same scramble, and intervals follow WCA rules (no same-face consecutive moves, no same-axis triples)

### App-layer design

- **Gesture arbitration**: session-based multi-finger tracking driven by raycast hit results — sticker hits turn layers, empty-space drags orbit the view, and two-finger pinches zoom, without interfering with each other
- **Scene reuse**: same-size state changes rebuild in place; switching sizes rebuilds the whole scene; materials are cached per skin, making skin switching essentially free
- **Collision shape discipline**: sticker collision shapes use a "full-cell coverage, flush with the surface" strategy, avoiding the classic mis-hit problem where perspective exposes neighboring faces

### Solver design

CubeSolve is a thin adapter between CubeKit and a third-party solver. It does exactly three things: encode a `CubeState` as a Kociemba facelet string, translate the underlying errors into this project's error surface, and decode the result back into an `Algorithm`. The algorithm itself comes from the Kociemba two-phase implementation vendored into `Vendor/SwiftTB2PKit`.

- **Facelet convention**: the external notation orders faces as `U R F D L B` while this project's `Face` raw values run `u d f b r l`. Only the block order differs — the row/column reading within each face is identical — so the mapping is a single block reordering
- **Crash isolation**: the underlying `TB2P.tables` calls `fatalError` on load failure, which callers cannot catch. `CubeSolve.isAvailable` checks the resource is bundled first and throws instead of taking the host app down
- **Table lifecycle**: the 21 MB lookup table is copied from the bundle into Caches by `prepare()` before loading. iOS purges Caches, so `prepare()` must run **on every launch**, not just once
- **Not optimal**: the two-phase pruning tables are admissible but loose lower bounds; when one overestimates, entire shallow search levels get pruned and the solution can be longer than optimal. Random scrambles measure 20–24 moves, 22.6 on average

## Project Layout

```
iCube/
├── project.yml              # XcodeGen project definition (single source of truth)
├── CubeKit/                 # Core algorithm package (SwiftPM)
│   ├── Sources/CubeKit/     # Cube state / moves / notation / scrambles / orientation / facelets
│   └── Tests/CubeKitTests/  # 96 unit tests
├── CubeSolve/               # Solver adapter package (SwiftPM), depends on CubeKit + the vendored solver
├── Vendor/
│   └── SwiftTB2PKit/        # Third-party Kociemba two-phase solver (MIT); see VENDORED.md
├── iCube/                   # Application layer
│   ├── Practice/            # Practice tab: scene, gestures, timer, skins, demo board
│   ├── Solve/               # Restore assistant: net entry, solving, step playback
│   ├── Tutorial/            # Tutorial: data, demo model, views
│   ├── Stats/               # Solve records and statistics
│   └── Assets.xcassets/     # App icon and other assets
├── iCubeTests/              # App-layer unit tests (65 tests)
└── Tools/                   # Asset generation scripts (see below)
```

### Regenerating assets

```bash
# App icon (1024px PNG) — output is byte-identical to the committed asset
swift Tools/make_icon.swift iCube/Assets.xcassets/AppIcon.appiconset/AppIcon.png

# Turn sound effects — NOTE: superseded, see the header of the script
swift Tools/make_sounds.swift <output-dir>
```

`make_icon.swift` is the live generator for the shipped icon. `make_sounds.swift` is
kept for historical reference only: the three `turn_*.wav` files in the app were taken
from a real magnetic-cube recording and are **not** reproducible from this script.

## Getting Started

### Requirements

- macOS 14+
- Xcode 26+ (with the iOS 18 SDK; the vendored solver package declares `swift-tools-version: 6.2` and needs a Swift 6.2 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A development team for on-device signing (update `DEVELOPMENT_TEAM` in `project.yml`)

### Build & Run

```bash
# 1. Generate the Xcode project (the project file is not committed;
#    re-run after any change to project.yml)
xcodegen generate

# 2. Open the project
open iCube.xcodeproj

# 3. Pick a device and press Cmd+R
```

Building a device build from the command line:

```bash
xcodebuild -project iCube.xcodeproj -scheme iCube \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

### Running Tests

```bash
# CubeKit package tests (runs on macOS directly, fastest)
cd CubeKit && swift test

# CubeSolve tests (end-to-end: random scramble → solve → apply → assert solved)
cd CubeSolve && swift test

# Full test suite (includes the app layer; requires a simulator)
xcodebuild test -project iCube.xcodeproj -scheme iCube \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

> Solver tests are roughly 20× slower in a debug build (`-Onone`). Add `-c release` to see realistic timings.

## Testing Strategy

- **CubeKit (96 tests)**: geometry and sticker-index invariants, turn-permutation correctness across all supported sizes, notation parse round-trips, size-dependent wide-move semantics, scramble solvability and interval rules, color-count conservation under random multi-size turning, facelet-string round-trips
- **CubeSolve (13 tests)**: end-to-end solvability of random scrambles, rejection of illegal states (single flipped edge / single twisted corner), rejection of non-3×3 sizes, solution-string reparse consistency, solutions restricted to outer face turns
- **App layer (65 tests)**: gesture intent arbitration (including back-facing hit filtering), scene construction and sticker reconciliation, per-case tutorial validation, the practice-session state machine, net coordinate mapping, and the restore-entry paint / validate / solve flow end to end

## Implementation Notes

- Cube orientation accumulates as integer rotation matrices (`Rotation`) and is converted to quaternions only once for rendering, eliminating floating-point drift and resulting sticker misalignment
- Layer membership is determined by the projection of a cubie's center onto the face normal (inner layers map directly to `depth` notation), independent of the reference face's orientation
- The timer is driven per-frame by `TimelineView`, with zero overhead while paused

## License

Copyright the author. No open-source license is attached.

`Vendor/SwiftTB2PKit/` is third-party code used under the MIT License, copyright
Michael Baumgärtner. See `Vendor/SwiftTB2PKit/LICENSE.md` for the full text.
