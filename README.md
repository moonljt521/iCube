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

- **Photo scan**: photograph the six faces one by one; the state is read automatically and dropped into the entry net for review. Shoot in any order and at any angle — each face is recognised independently and the six are reassembled by exhaustive search
- **Manual entry**: paint the standard unfolded net cell by cell — tap or drag to brush continuously. The six centers come pre-filled with the standard color scheme, so only 48 cells are left
- **Live validation**: cell count and per-color counts are reported as you go; solving unlocks only once the net is full and balanced
- **Short solutions**: Kociemba two-phase algorithm — typically 20–24 moves for a random scramble, roughly 26 ms per solve
- **Text + animated steps**: a numbered step strip highlights and auto-scrolls as the animation plays, with replay, reset, and three speed settings
- Illegal states (a single flipped edge, a single twisted corner, a parity error) are rejected by the solver with a plain-language explanation

#### How the photo scan works

Recognising a cube from photos is two separate problems, and the hard one is not colour
classification:

1. **Colour classification** — the six center stickers are physically guaranteed to be six
   different colors, so they are used as clustering seeds. This makes the color space
   self-calibrating per shot. Each cell is sampled by trimming the darkest and brightest
   20% before averaging in **linear** RGB (the gaps between stickers and the specular
   highlights are what drag a naive mean off), and the whole result is white-balanced in
   linear RGB — the one space where a diagonal correction is exact, which is why the
   classic XYZ von Kries correction leaves ~9 Lab units of residual error where this
   leaves 0.
2. **Orientation** — you cannot tell from a single photo how far a face was rotated, and
   three faces are never enough to infer the other three. So the rotation is not guessed:
   all 4⁶ orientation combinations are enumerated and filtered through the reachability
   test (centers in place, exactly nine of each color, valid cubie structure, corner-twist
   and edge-flip sums, permutation parity). Exactly one survives, in under 20 ms.

Because the second step enumerates rather than assumes, shooting order, phone orientation
and face rotation all drop out for free.

## Tech Stack & Architecture

| Layer | Technology |
|-------|------------|
| UI | SwiftUI (iOS 18+) |
| 3D rendering | RealityKit (`RealityView` + camera content) |
| Persistence | SwiftData (solve records), UserDefaults (skin / size preferences) |
| Core algorithms | CubeKit (local SwiftPM package) |
| Photo recognition | CubeScan (local SwiftPM package, zero UI dependencies) + AVFoundation |
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
- **Viewfinder geometry**: the guide box is a centered square, and both a 90° rotation about the center and aspect-fit letterboxing map the center to the center. So the sampled region is *always* a centered square in the camera frame, and the code deliberately never tries to work out which way the frame is rotated — a wrong guess would produce a mirror, which no downstream step can undo, whereas a rotation is absorbed by the orientation enumeration. Not tracking the rotation removes the one place that could silently be wrong
- **Frame sampling off the main thread**: the camera callback runs on a dedicated serial queue and samples 9 cells per frame directly out of the locked `CVPixelBuffer` (no frame copies); only the throttled result (~10 Hz) hops back to the main actor. The viewfinder geometry is *pushed* to that queue rather than recomputed on it

### Solver design

CubeSolve is a thin adapter between CubeKit and a third-party solver. It does exactly three things: encode a `CubeState` as a Kociemba facelet string, translate the underlying errors into this project's error surface, and decode the result back into an `Algorithm`. The algorithm itself comes from the Kociemba two-phase implementation vendored into `Vendor/SwiftTB2PKit`.

- **Facelet convention**: the external notation orders faces as `U R F D L B` while this project's `Face` raw values run `u d f b r l`. Only the block order differs — the row/column reading within each face is identical — so the mapping is a single block reordering
- **Crash isolation**: the underlying `TB2P.tables` calls `fatalError` on load failure, which callers cannot catch. `CubeSolve.isAvailable` checks the resource is bundled first and throws instead of taking the host app down
- **Table lifecycle**: the 21 MB lookup table is copied from the bundle into Caches by `prepare()` before loading. iOS purges Caches, so `prepare()` must run **on every launch**, not just once
- **Not optimal**: the two-phase pruning tables are admissible but loose lower bounds; when one overestimates, entire shallow search levels get pruned and the solution can be longer than optimal. Random scrambles measure 20–24 moves, 22.6 on average

### Photo recognition design

CubeScan is a pure algorithm package with zero UI dependencies — Lab colour math, sticker sampling, clustering, orientation enumeration and viewfinder geometry all run and are tested on macOS, without a simulator or a camera. The app layer (`iCube/Scan/`) is deliberately thin: it captures frames, feeds them in, and presents the result.

- **Everything happens in Lab, not sRGB**: equal sRGB distance does not mean equal perceived difference (two dark blues 30 code values apart look identical; two pale yellows the same distance apart clearly do not). Lab also splits lightness from chroma, which is what makes the white-point correction meaningful
- **White balance is done in linear RGB, not XYZ**: an illuminant multiplies linear RGB channels, which is exactly what a camera's white balance corrects for. The classic von Kries diagonal correction performed in XYZ is only an approximation of that — measured residual error under warm light is ~9 Lab units, versus 0 in linear RGB
- **Trimmed-mean sampling**: a sticker cell's sampling region mixes sticker, black plastic gap and specular highlight. Sorting by luminance and dropping 20% from each end removes both tails; the mean is then taken in linear RGB, because averaging Lab is not meaningful
- **The nine-per-color rule is a hard constraint, not a heuristic**: a 3×3 cube has exactly nine stickers of each color, so cluster sizes that come out wrong are repaired by moving the most borderline sample
- **Orientation by enumeration**: 4⁶ combinations filtered by the reachability test. Brute force is fine here — the legality check fails fast on the first edge for almost every combination, so a full sweep is well under 20 ms

## Project Layout

```
iCube/
├── project.yml              # XcodeGen project definition (single source of truth)
├── CubeKit/                 # Core algorithm package (SwiftPM)
│   ├── Sources/CubeKit/     # Cube state / moves / notation / scrambles / orientation / facelets / legality
│   └── Tests/CubeKitTests/  # 111 unit tests
├── CubeScan/                # Photo recognition package (SwiftPM), depends on CubeKit
│   ├── Sources/CubeScan/    # Lab color / sticker sampling / clustering / facelet assembly / viewfinder geometry
│   └── Tests/CubeScanTests/ # 48 unit tests
├── CubeSolve/               # Solver adapter package (SwiftPM), depends on CubeKit + the vendored solver
├── Vendor/
│   └── SwiftTB2PKit/        # Third-party Kociemba two-phase solver (MIT); see VENDORED.md
├── iCube/                   # Application layer
│   ├── Practice/            # Practice tab: scene, gestures, timer, skins, demo board
│   ├── Scan/                # Photo scan: capture session, preview bridge, orchestration, UI
│   ├── Solve/               # Restore assistant: net entry, solving, step playback
│   ├── Tutorial/            # Tutorial: data, demo model, views
│   ├── Stats/               # Solve records and statistics
│   └── Assets.xcassets/     # App icon and other assets
├── iCubeTests/              # App-layer unit tests (68 tests)
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

# CubeScan package tests (pure algorithms, also runs on macOS)
cd CubeScan && swift test

# CubeSolve tests (end-to-end: random scramble → solve → apply → assert solved)
cd CubeSolve && swift test

# Full test suite (includes the app layer; requires a simulator)
xcodebuild test -project iCube.xcodeproj -scheme iCube \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

> Solver tests are roughly 20× slower in a debug build (`-Onone`). Add `-c release` to see realistic timings.

> On machines where `sandbox-exec` is unavailable, SwiftPM and Xcode both fail to launch
> their macro / manifest plugin hosts. Add `--disable-sandbox` to `swift test`, and
> `OTHER_SWIFT_FLAGS="-disable-sandbox"` to `xcodebuild`.

## Testing Strategy

- **CubeKit (111 tests)**: geometry and sticker-index invariants, turn-permutation correctness across all supported sizes, notation parse round-trips, size-dependent wide-move semantics, scramble solvability and interval rules, color-count conservation under random multi-size turning, facelet-string round-trips, and reachability (every outer face move preserves legality; single flipped edges / single twisted corners / swapped pairs are rejected; the orientation sums are checked by exhaustive search rather than by hand-derived rules)
- **CubeScan (48 tests)**: sRGB↔Lab round-trips against published reference values, white-point adaptation cancelling a known illuminant, sticker sampling under black gaps and specular highlights, self-calibrating clustering across daylight / warm / cool / dim lighting with sensor noise, capture-order and rotation independence, the nine-per-color repair rule pulling a boundary sample back, and 4⁶ orientation enumeration resolving to exactly one legal state
- **CubeSolve (13 tests)**: end-to-end solvability of random scrambles, rejection of illegal states (single flipped edge / single twisted corner), rejection of non-3×3 sizes, solution-string reparse consistency, solutions restricted to outer face turns
- **App layer (68 tests)**: gesture intent arbitration (including back-facing hit filtering), scene construction and sticker reconciliation, per-case tutorial validation, the practice-session state machine, net coordinate mapping, the restore-entry paint / validate / solve flow end to end, and the scan → recognise → entry-net handoff

## Implementation Notes

- Cube orientation accumulates as integer rotation matrices (`Rotation`) and is converted to quaternions only once for rendering, eliminating floating-point drift and resulting sticker misalignment
- Layer membership is determined by the projection of a cubie's center onto the face normal (inner layers map directly to `depth` notation), independent of the reference face's orientation
- The timer is driven per-frame by `TimelineView`, with zero overhead while paused

## License

Copyright the author. No open-source license is attached.

`Vendor/SwiftTB2PKit/` is third-party code used under the MIT License, copyright
Michael Baumgärtner. See `Vendor/SwiftTB2PKit/LICENSE.md` for the full text.
