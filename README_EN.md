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

## Tech Stack & Architecture

| Layer | Technology |
|-------|------------|
| UI | SwiftUI (iOS 18+) |
| 3D rendering | RealityKit (`RealityView` + camera content) |
| Persistence | SwiftData (solve records), UserDefaults (skin / size preferences) |
| Core algorithms | CubeKit (local SwiftPM package) |

### CubeKit design

CubeKit is a pure Swift algorithm package, fully decoupled from the app layer with no UIKit / RealityKit dependencies:

- **Geometry-derived correctness**: every turn permutation is derived at runtime by rotating integer lattice coordinates 90° about an axis — no hand-copied lookup tables anywhere; correctness is guaranteed by geometric invariants
- **N×N generalization**: state, layer membership, notation (including `2R` inner-layer and `Rw` wide moves), and scrambles are all parameterized by cube size; the size is inferred from the sticker count (6N²), keeping the data model backward compatible
- **Deterministic scrambles**: seedable SplitMix64 randomness — the same seed reproduces the same scramble, and intervals follow WCA rules (no same-face consecutive moves, no same-axis triples)

### App-layer design

- **Gesture arbitration**: session-based multi-finger tracking driven by raycast hit results — sticker hits turn layers, empty-space drags orbit the view, and two-finger pinches zoom, without interfering with each other
- **Scene reuse**: same-size state changes rebuild in place; switching sizes rebuilds the whole scene; materials are cached per skin, making skin switching essentially free
- **Collision shape discipline**: sticker collision shapes use a "full-cell coverage, flush with the surface" strategy, avoiding the classic mis-hit problem where perspective exposes neighboring faces

## Project Layout

```
iCube/
├── project.yml              # XcodeGen project definition (single source of truth)
├── CubeKit/                 # Core algorithm package (SwiftPM)
│   ├── Sources/CubeKit/     # Cube state / moves / notation / scrambles / orientation
│   └── Tests/CubeKitTests/  # 79 unit tests
├── iCube/                   # Application layer
│   ├── Practice/            # Practice tab: scene, gestures, timer, skins
│   ├── Tutorial/            # Tutorial: data, demo model, views
│   ├── Stats/               # Solve records and statistics
│   └── Assets.xcassets/     # App icon and other assets
└── iCubeTests/              # App-layer unit tests (38 tests)
```

## Getting Started

### Requirements

- macOS 14+
- Xcode 16+ (with the iOS 18 SDK)
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

# Full test suite (includes the app layer; requires a simulator)
xcodebuild test -project iCube.xcodeproj -scheme iCube \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Testing Strategy

- **CubeKit (79 tests)**: geometry and sticker-index invariants, turn-permutation correctness across all supported sizes, notation parse round-trips, size-dependent wide-move semantics, scramble solvability and interval rules, color-count conservation under random multi-size turning
- **App layer (38 tests)**: gesture intent arbitration (including back-facing hit filtering), scene construction and sticker reconciliation, per-case tutorial validation, and the practice-session state machine

## Implementation Notes

- Cube orientation accumulates as integer rotation matrices (`Rotation`) and is converted to quaternions only once for rendering, eliminating floating-point drift and resulting sticker misalignment
- Layer membership is determined by the projection of a cubie's center onto the face normal (inner layers map directly to `depth` notation), independent of the reference face's orientation
- The timer is driven per-frame by `TimelineView`, with zero overhead while paused

## License

Copyright the author. No open-source license is attached.
