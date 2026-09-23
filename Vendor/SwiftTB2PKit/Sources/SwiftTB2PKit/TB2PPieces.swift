// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

// This module defines the basic enumerations for colors, corners, edges, and
// facelets of a 3x3x3 Rubik's Cube.

import Foundation

/// Represents the six colors of a 3x3x3 Rubik's Cube.
/// The order and assignment follow the standard notation:
/// U = Up, R = Right, F = Front, D = Down, L = Left, B = Back
public enum TB2PColor: Int, CaseIterable, Codable, Sendable {
    /// Up face
    case U = 0
    /// Right face
    case R = 1
    /// Front face
    case F = 2
    /// Down face
    case D = 3
    /// Left face
    case L = 4
    /// Back face
    case B = 5

    public static func from(character: Character) -> TB2PColor? {
        switch character {
        case "U": .U
        case "R": .R
        case "F": .F
        case "D": .D
        case "L": .L
        case "B": .B
        default: nil
        }
    }
}

/// Represents the eight corner pieces of a 3x3x3 Rubik's Cube.
/// The names indicate the three adjacent faces, e.g., URF = Up-Right-Front.
public enum TB2PCorner: Int, CaseIterable, Comparable, Codable, Sendable {
    case URF = 0  // Up-Right-Front
    case UFL = 1  // Up-Front-Left
    case ULB = 2  // Up-Left-Back
    case UBR = 3  // Up-Back-Right
    case DFR = 4  // Down-Front-Right
    case DLF = 5  // Down-Left-Front
    case DBL = 6  // Down-Back-Left
    case DRB = 7  // Down-Right-Back

    public static func < (lhs: TB2PCorner, rhs: TB2PCorner) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Represents the twelve edge pieces of a 3x3x3 Rubik's Cube.
/// The names indicate the two adjacent faces, e.g., UR = Up-Right.
public enum TB2PEdge: Int, CaseIterable, Comparable, Codable, Sendable {
    case UR = 0  // Up-Right
    case UF = 1  // Up-Front
    case UL = 2  // Up-Left
    case UB = 3  // Up-Back
    case DR = 4  // Down-Right
    case DF = 5  // Down-Front
    case DL = 6  // Down-Left
    case DB = 7  // Down-Back
    case FR = 8  // Front-Right
    case FL = 9  // Front-Left
    case BL = 10  // Back-Left
    case BR = 11  // Back-Right

    public static func < (lhs: TB2PEdge, rhs: TB2PEdge) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Represents the 54 facelets (stickers) of a 3x3x3 Rubik's Cube.
/// The notation follows the order: U1-U9, R1-R9, F1-F9, D1-D9, L1-L9, B1-B9.
/// Each facelet value corresponds to a unique position on the cube.
public enum TB2PFacelet: Int, CaseIterable, Codable, Sendable {
    // Up face facelets
    case U1 = 0
    case U2, U3, U4, U5, U6, U7, U8, U9
    // Right face facelets
    case R1 = 9
    case R2, R3, R4, R5, R6, R7, R8, R9
    // Front face facelets
    case F1 = 18
    case F2, F3, F4, F5, F6, F7, F8, F9
    // Down face facelets
    case D1 = 27
    case D2, D3, D4, D5, D6, D7, D8, D9
    // Left face facelets
    case L1 = 36
    case L2, L3, L4, L5, L6, L7, L8, L9
    // Back face facelets
    case B1 = 45
    case B2, B3, B4, B5, B6, B7, B8, B9
}
