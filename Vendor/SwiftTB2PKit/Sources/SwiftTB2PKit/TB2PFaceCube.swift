// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

// This file defines the FaceCube class, which represents a Rubik's Cube by
// its facelets (stickers). It provides conversion between a facelet-based
// representation and a cubie-based representation (CubieCube).

import Foundation

/// Represents a Rubik's Cube by its facelets (stickers).
///
/// Provides conversion to and from the cubie-based representation (CubieCube).
/// Used for parsing, displaying, and validating cube states as strings.
public struct TB2PFaceCube: CustomStringConvertible {

    /// The facelet array, 54 elements, each representing a color.
    private var facelets: [TB2PColor]

    /// Initializes a FaceCube from a string of 54 facelet characters.
    ///
    /// If no string is provided, initializes a solved cube. Throws an error
    /// if the string is not exactly 54 characters or contains invalid chars.
    ///
    /// - Parameter cubeString: The facelet string (default: solved cube).
    /// - Throws: TB2PError if the string is invalid.
    public init(cubeString: String = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB") throws {
        guard cubeString.count == 54 else {
            throw TB2PError.faceCubeInvalidFacelets(cubeString)
        }
        self.facelets = try cubeString.enumerated().map { i, c in
            switch c {
            case "U": return .U
            case "R": return .R
            case "F": return .F
            case "D": return .D
            case "L": return .L
            case "B": return .B
            default:
                throw TB2PError.faceCubeInvalidFacelet(String(c), i)
            }
        }
    }

    /// Initializes a FaceCube from a CubieCube representation.
    ///
    /// Converts the given CubieCube to a facelet-based representation.
    ///
    /// - Parameter cubieCube: The CubieCube to convert.
    public init(from cubieCube: TB2PCubieCube) {
        do {
            try self.init()
        } catch {
            fatalError("TB2PFaceCube init failed: \(error)")
        }
        fromCubieCube(cubieCube)
    }

    /// Updates this FaceCube to match the given CubieCube state.
    ///
    /// - Parameter cubieCube: The CubieCube to convert.
    private mutating func fromCubieCube(_ cubieCube: TB2PCubieCube) {
        // Corners
        for i in 0..<8 {
            let corner = cubieCube.cp[i].rawValue
            let orientation = cubieCube.co[i]
            for k in 0..<3 {
                let faceletIndex = TB2P.cornerFacelet[i][(k + orientation).wrappedMod(by: 3)].rawValue
                self.facelets[faceletIndex] = TB2P.cornerColor[corner][k]
            }
        }
        // Edges
        for i in 0..<12 {
            let edge = cubieCube.ep[i].rawValue
            let orientation = cubieCube.eo[i]
            for k in 0..<2 {
                let faceletIndex = TB2P.edgeFacelet[i][(k + orientation).wrappedMod(by: 2)].rawValue
                self.facelets[faceletIndex] = TB2P.edgeColor[edge][k]
            }
        }
    }

    /// Returns the facelet string representation of the cube.
    public var description: String {
        return facelets.map { c in
            switch c {
            case .U: return "U"
            case .R: return "R"
            case .F: return "F"
            case .D: return "D"
            case .L: return "L"
            case .B: return "B"
            }
        }.joined()
    }

    /// Converts this FaceCube to a CubieCube representation.
    ///
    /// Returns a new CubieCube with the same state as this FaceCube.
    /// Used for solving and validation.
    public func toCubieCube() -> TB2PCubieCube {
        let cubieCube = TB2PCubieCube()

        // Corners
        for i in 0..<8 {
            var orientation = 0
            for o in 0..<3 {
                if facelets[TB2P.cornerFacelet[i][o].rawValue] == .U
                    || facelets[TB2P.cornerFacelet[i][o].rawValue] == .D
                {
                    orientation = o
                    break
                }
            }
            let color1 = facelets[TB2P.cornerFacelet[i][(orientation + 1).wrappedMod(by: 3)].rawValue]
            let color2 = facelets[TB2P.cornerFacelet[i][(orientation + 2).wrappedMod(by: 3)].rawValue]
            for c in 0..<8 {
                if color1 == TB2P.cornerColor[c][1] && color2 == TB2P.cornerColor[c][2] {
                    cubieCube.cp[i] = TB2PCorner(rawValue: c)!
                    cubieCube.co[i] = orientation
                    break
                }
            }
        }
        // Edges
        for i in 0..<12 {
            for j in 0..<12 {
                if facelets[TB2P.edgeFacelet[i][0].rawValue] == TB2P.edgeColor[j][0]
                    && facelets[TB2P.edgeFacelet[i][1].rawValue] == TB2P.edgeColor[j][1]
                {
                    cubieCube.ep[i] = TB2PEdge(rawValue: j)!
                    cubieCube.eo[i] = 0
                    break
                }
                if facelets[TB2P.edgeFacelet[i][0].rawValue] == TB2P.edgeColor[j][1]
                    && facelets[TB2P.edgeFacelet[i][1].rawValue] == TB2P.edgeColor[j][0]
                {
                    cubieCube.ep[i] = TB2PEdge(rawValue: j)!
                    cubieCube.eo[i] = 1
                    break
                }
            }
        }
        return cubieCube
    }
}

extension TB2P {
    /// Maps corner positions to facelet positions.
    fileprivate static let cornerFacelet: [[TB2PFacelet]] = [
        [.U9, .R1, .F3],
        [.U7, .F1, .L3],
        [.U1, .L1, .B3],
        [.U3, .B1, .R3],
        [.D3, .F9, .R7],
        [.D1, .L9, .F7],
        [.D7, .B9, .L7],
        [.D9, .R9, .B7],
    ]

    /// Maps edge positions to facelet positions.
    fileprivate static let edgeFacelet: [[TB2PFacelet]] = [
        [.U6, .R2],
        [.U8, .F2],
        [.U4, .L2],
        [.U2, .B2],
        [.D6, .R8],
        [.D2, .F8],
        [.D4, .L8],
        [.D8, .B8],
        [.F6, .R4],
        [.F4, .L6],
        [.B6, .L4],
        [.B4, .R6],
    ]

    /// Maps corner positions to colors.
    fileprivate static let cornerColor: [[TB2PColor]] = [
        [.U, .R, .F],
        [.U, .F, .L],
        [.U, .L, .B],
        [.U, .B, .R],
        [.D, .F, .R],
        [.D, .L, .F],
        [.D, .B, .L],
        [.D, .R, .B],
    ]

    /// Maps edge positions to colors.
    fileprivate static let edgeColor: [[TB2PColor]] = [
        [.U, .R],
        [.U, .F],
        [.U, .L],
        [.U, .B],
        [.D, .R],
        [.D, .F],
        [.D, .L],
        [.D, .B],
        [.F, .R],
        [.F, .L],
        [.B, .L],
        [.B, .R],
    ]
}
