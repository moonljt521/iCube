# SwiftTB2PKit

A pure Swift implementation of Herbert Kociemba's two-phase algorithm for solving the Rubik's Cube.

This module is a Swift port of [cube-solver](https://github.com/tcbegley/cube-solver) by Tom Begley (MIT License, no source code was copied). 

## Description

TB2P implements the two-phase algorithm in Swift and is based on the original Python implementation. The algorithm efficiently solves the Rubik's Cube and is suitable for integration into iOS or macOS projects.

Licensed under the [MIT License](LICENSE.md).

## Discussion

**Usage**

```swift
import SwiftTB2PKit
let facelets = "DFLRUBRDFRLDURRLRRUFDFFLBDFULUUDULBURBBBLRBFLFLBDBDFUD"
let solver = try! TB2PSolver(facelets: facelets)
let solution = try! solver.search()
print(solution)
>>> "U2 B' U F L' U2 L' B' U L U R2 U' F2 B2 U' B2 R2 U' R2 F2 U L2 U"
```

The facelet string is a 54-character string, where any character represents one sticker on the Rubik’s Cube. The characters U, R, F, D, L, and B correspond to the Upper, Right, Front, Down, Left, and Back faces of the cube, respectively. A standard color scheme is used to map each face to a color: the Upper face is white, the Right face is red, the Front face is green, the Down face is yellow, the Left face is orange, and the Back face is blue. This means that a character in the string not only identifies a position on the cube but also implicitly encodes the color of that sticker according to this face orientation.

Each character corresponds to one of the 54 stickers on the cube in the follwing order:

```
               +----+----+----+
               |  0 |  1 |  2 |
               +----+----+----+
               |  3 |  4 |  5 |
               +----+----+----+
               |  6 |  7 |  8 |
+----+----+----+----+----+----+----+----+----+----+----+----+           +---+
| 36 | 37 | 38 | 18 | 19 | 20 |  9 | 10 | 11 | 45 | 46 | 47 |           | U |
+----+----+----+----+----+----+----+----+----+----+----+----+       +---+---+---+---+
| 39 | 40 | 41 | 21 | 22 | 23 | 12 | 13 | 14 | 48 | 49 | 50 |       | L | F | R | B | 
+----+----+----+----+----+----+----+----+----+----+----+----+       +---+---+---+---+
| 42 | 43 | 44 | 24 | 25 | 26 | 15 | 16 | 17 | 51 | 52 | 53 |           | D |
+----+----+----+----+----+----+----+----+----+----+----+----+           +---+
               | 27 | 28 | 29 |
               +----+----+----+
               | 30 | 31 | 32 |
               +----+----+----+
               | 33 | 34 | 35 |
               +----+----+----+
```

For example, a completely solved cube is represented by the string `"UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"`.

The `search` function searches for a valid solution to the given cube state within the configured bounds. By default, it explores solutions up to a maximum depth of 25 moves and stops if no solution is found within five seconds. If a solution is successfully discovered, the function returns it as a string of cube moves.

The solution is expressed using standard Singmaster notation, where each letter represents a quarter-turn of one face of the cube. The basic moves are **U**, **R**, **F**, **D**, **L**, and **B**, referring to the Up, Right, Front, Down, Left, and Back faces. A letter on its own denotes a 90-degree clockwise turn of that face. A letter followed by an apostrophe (for example R') denotes a 90-degree counter-clockwise turn. A letter followed by the number 2 (such as U2) indicates a 180-degree turn. Moves are applied in the order they appear in the string, from left to right.
