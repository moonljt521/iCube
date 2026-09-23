// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

// This file defines the CoordCube class, which represents the state of a
// Rubik's Cube in coordinate space.

import Foundation

/// Represents a Rubik's Cube in coordinate space, including twist, flip,
/// slice coordinates, and edge/corner permutations.
///
/// This compact representation is used for efficient move application and
/// table lookups during the solving process.
public final class TB2PCoordCube {
    var twist: Int
    var flip: Int
    var udslice: Int
    var edge4: Int
    var edge8: Int
    var corner: Int

    /// Initializes a new coordinate cube with the given coordinate values.
    ///
    /// - Parameters:
    ///   - twist: The twist coordinate (default: 0).
    ///   - flip: The flip coordinate (default: 0).
    ///   - udslice: The UDSlice coordinate (default: 0).
    ///   - edge4: The edge4 coordinate (default: 0).
    ///   - edge8: The edge8 coordinate (default: 0).
    ///   - corner: The corner coordinate (default: 0).
    public init(
        twist: Int = 0,
        flip: Int = 0,
        udslice: Int = 0,
        edge4: Int = 0,
        edge8: Int = 0,
        corner: Int = 0
    ) {
        self.twist = twist
        self.flip = flip
        self.udslice = udslice
        self.edge4 = edge4
        self.edge8 = edge8
        self.corner = corner
    }

    /// Creates a coordinate cube from a cubie cube representation.
    ///
    /// - Parameter cubieCube: The cubie cube to convert.
    /// - Returns: A TB2PCoordCube with coordinates matching the cubie cube.
    public static func fromCubieCube(_ cubieCube: TB2PCubieCube) -> TB2PCoordCube {
        return TB2PCoordCube(
            twist: cubieCube.twist,
            flip: cubieCube.flip,
            udslice: cubieCube.udslice,
            edge4: cubieCube.edge4,
            edge8: cubieCube.edge8,
            corner: cubieCube.corner
        )
    }

    /// Applies a move to the coordinate cube, updating all coordinates.
    ///
    /// - Parameter move: The move index to apply (0...17 for standard moves).
    public func move(_ move: Int) {
        self.twist = TB2P.tables.twistMove[self.twist][move]
        self.flip = TB2P.tables.flipMove[self.flip][move]
        self.udslice = TB2P.tables.udsliceMove[self.udslice][move]
        self.edge4 = TB2P.tables.edge4Move[self.edge4][move]
        self.edge8 = TB2P.tables.edge8Move[self.edge8][move]
        self.corner = TB2P.tables.cornerMove[self.corner][move]
    }
}
