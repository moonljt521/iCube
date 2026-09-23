// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

// This file defines the CubieCube class, which represents the state of a
// Rubik's Cube on the cubie level. It includes permutation and orientation
// of corners and edges, as well as various coordinate systems used in cube
// solving algorithms.

import Foundation

// swiftlint: disable file_length

// swiftlint: disable type_body_length
/// Represents a Rubik's Cube on the cubie level, including permutation and
/// orientation of corners and edges.
public class TB2PCubieCube {
    /// Corner permutation: cp[i] gives
    /// the corner occupying position i.
    var cp: [TB2PCorner]
    /// Corner orientation: co[i] gives
    /// the orientation of the corner
    /// at position i (0, 1, or 2).
    var co: [Int]
    /// Edge permutation: ep[i] gives
    /// the edge occupying position i.
    var ep: [TB2PEdge]
    /// Edge orientation: eo[i] gives
    /// the orientation of the edge
    /// at position i (0 or 1).
    var eo: [Int]

    /// Initializes a CubieCube with the given corner and edge permutation and
    /// orientation. If no parameters are provided, the cube is initialized in
    /// the solved state.
    ///
    /// - Parameters:
    ///   - cp: Corner permutation array. Each value specifies which corner
    ///             occupies each position.
    ///   - co: Corner orientation array. Each value (0, 1, 2) specifies the
    ///             orientation of the corner at each position.
    ///   - ep: Edge permutation array. Each value specifies which edge
    ///             occupies each position.
    ///   - eo: Edge orientation array. Each value (0 or 1) specifies the
    ///             orientation of the edge at each position.
    public init(cp: [TB2PCorner]? = nil, co: [Int]? = nil, ep: [TB2PEdge]? = nil, eo: [Int]? = nil) {
        if let cp = cp, let co = co, let ep = ep, let eo = eo {
            self.cp = cp
            self.co = co
            self.ep = ep
            self.eo = eo
        } else {
            self.cp = [.URF, .UFL, .ULB, .UBR, .DFR, .DLF, .DBL, .DRB]
            self.co = Array(repeating: 0, count: 8)
            self.ep = [.UR, .UF, .UL, .UB, .DR, .DF, .DL, .DB, .FR, .FL, .BL, .BR]
            self.eo = Array(repeating: 0, count: 12)
        }
    }

    /// Applies the corner permutation and orientation of `other` to this cube.
    ///
    /// Updates the current cube's corner permutation and orientation by
    /// composing it with `other`. Used for move application and cube
    /// multiplication.
    ///
    /// - Parameter other: The cube whose corner state is applied.
    public func cornerMultiply(_ other: TB2PCubieCube) {
        let cornerPermutation = (0..<8).map {
            cp[other.cp[$0]]
        }
        let cornerOrientation = (0..<8).map {
            (co[other.cp[$0]] + other.co[$0]).wrappedMod(by: 3)
        }
        cp = cornerPermutation
        co = cornerOrientation
    }

    /// Applies the edge permutation and orientation of `other` to this cube.
    ///
    /// Updates the current cube's edge permutation and orientation by
    /// composing it with `other`. Used for move application and cube
    /// multiplication.
    ///
    /// - Parameter other: The cube whose edge state is applied.
    public func edgeMultiply(_ other: TB2PCubieCube) {
        let edgePermutation = (0..<12).map {
            ep[other.ep[$0]]
        }
        let edgeOrientation = (0..<12).map {
            (eo[other.ep[$0]] + other.eo[$0]).wrappedMod(by: 2)
        }
        ep = edgePermutation
        eo = edgeOrientation
    }

    /// Applies the permutation and orientation of `other` to this cube.
    ///
    /// Updates both corners and edges by composing the current cube with
    /// `other`. Used for move application and cube multiplication.
    ///
    /// - Parameter other: The cube whose state is applied.
    public func multiply(_ other: TB2PCubieCube) {
        cornerMultiply(other)
        edgeMultiply(other)
    }

    /// Applies one of the six basic face moves (U, R, F, D, L, B) to the cube.
    ///
    /// - Parameter index: The move index (0...5) corresponding to
    ///     U, R, F, D, L, B.
    public func move(_ index: Int) {
        multiply(TB2PCubieCube.moveCube[index])
    }

    /// Returns the inverse of the current cube state.
    ///
    /// The inverse undoes all moves and restores the cube to its previous
    /// state. Useful for algorithms and verification.
    ///
    /// - Returns: A new TB2PCubieCube representing the inverse state.
    public func inversed() -> TB2PCubieCube {
        let cube = TB2PCubieCube()
        for e in 0..<12 {
            cube.ep[ep[e]] = TB2PEdge(rawValue: e)!
        }
        for e in 0..<12 {
            cube.eo[e] = eo[cube.ep[e]]
        }
        for c in 0..<8 {
            cube.cp[cp[c]] = TB2PCorner(rawValue: c)!
        }
        for c in 0..<8 {
            let ori = co[cube.cp[c]]
            cube.co[c] = (-ori).wrappedMod(by: 3)
        }
        return cube
    }

    /// Computes the parity of the corner permutation.
    ///
    /// The corner parity is 0 if the number of swaps needed to solve the
    /// corners is even, and 1 if it is odd. The cube is only solvable if the
    /// corner parity matches the edge parity.
    public var cornerParity: Int {
        var s = 0
        for i in stride(from: 7, through: 1, by: -1) {
            for j in 0..<i where cp[j] > cp[i] {
                s += 1
            }
        }
        return s % 2
    }

    /// Computes the parity of the edge permutation.
    ///
    /// The edge parity is 0 if the number of swaps needed to solve the edges
    /// is even, and 1 if it is odd. The cube is only solvable if the edge
    /// parity matches the corner parity.
    public var edgeParity: Int {
        var s = 0
        for i in stride(from: 11, through: 1, by: -1) {
            for j in 0..<i where ep[j] > ep[i] {
                s += 1
            }
        }
        return s % 2
    }

    // MARK: - Phase 1 Coordinates

    /// The coordinate representing corner orientation (twist).
    ///
    /// Encodes the orientation of all 8 corners as a single integer in the
    /// range 0...2186. Used for efficient table lookups in the solver.
    public var twist: Int {
        get {
            return co.prefix(7).reduce(0) { 3 * $0 + $1 }
        }
        set {
            precondition(0 <= newValue && newValue < 2187, "twist out of range")
            var twist = newValue
            var total = 0
            for i in 0..<7 {
                let t = twist % 3
                co[6 - i] = t
                total += t
                twist = twist.floorDiv(by: 3)
            }
            co[7] = (-total).wrappedMod(by: 3)
        }
    }

    /// The coordinate representing edge orientation (flip).
    ///
    /// Encodes the orientation of all 12 edges as a single integer in the
    /// range 0...2047. Used for efficient table lookups in the solver.
    public var flip: Int {
        get {
            return eo.prefix(11).reduce(0) { 2 * $0 + $1 }
        }
        set {
            precondition(0 <= newValue && newValue < 2048, "flip out of range")
            var flip = newValue
            var total = 0
            for i in 0..<11 {
                let f = flip % 2
                eo[10 - i] = f
                total += f
                flip = flip.floorDiv(by: 2)
            }
            eo[11] = (-total).wrappedMod(by: 2)
        }
    }

    /// The coordinate representing the position (not order) of the 4 edges
    /// FR, FL, BL, BR (UD-slice edges).
    ///
    /// Used for phase 1 pruning and table lookups.
    public var udslice: Int {
        get {
            var udslice = 0
            var seen = 0
            for j in 0..<12 {
                if 8 <= ep[j].rawValue && ep[j].rawValue < 12 {
                    seen += 1
                } else if seen >= 1 {
                    udslice += choose(j, seen - 1)
                }
            }
            return udslice
        }
        set {
            precondition(0 <= newValue && newValue < choose(12, 4), "udslice out of range")
            let udsliceEdge: [TB2PEdge] = [.FR, .FL, .BL, .BR]
            let otherEdge: [TB2PEdge] = [.UR, .UF, .UL, .UB, .DR, .DF, .DL, .DB]
            for i in 0..<12 {
                ep[i] = .DB
            }
            var udslice = newValue
            var seen = 3
            for j in stride(from: 11, through: 0, by: -1) {
                if udslice - choose(j, seen) < 0 {
                    ep[j] = udsliceEdge[seen]
                    seen -= 1
                } else {
                    udslice -= choose(j, seen)
                }
            }
            var i = 0
            for j in 0..<12 where ep[j] == .DB {
                self.ep[j] = otherEdge[i]
                i += 1
            }
        }
    }

    // MARK: - Phase 2 Coordinates

    /// The coordinate representing permutation of the 4 UD-slice edges
    /// (FR, FL, BL, BR).
    ///
    /// Used for phase 2 pruning and table lookups.
    public var edge4: Int {
        get {
            let edge4 = Array(ep[8...11])
            var ret = 0
            for j in stride(from: 3, through: 1, by: -1) {
                let s = edge4[..<j].filter { $0 > edge4[j] }.count
                ret = j * (ret + s)
            }
            return ret
        }
        set {
            precondition(0 <= newValue && newValue < 24, "edge4 out of range")
            var edge4 = newValue
            var sliceedge: [TB2PEdge] = [.FR, .FL, .BL, .BR]
            var coeffs = [Int](repeating: 0, count: 3)
            for i in 1...3 {
                coeffs[i - 1] = edge4 % (i + 1)
                edge4 = edge4.floorDiv(by: i + 1)
            }
            var perm = [TB2PEdge](repeating: .FR, count: 4)
            for i in stride(from: 2, through: 0, by: -1) {
                perm[i + 1] = sliceedge.remove(at: i + 1 - coeffs[i])
            }
            perm[0] = sliceedge[0]
            for i in 0..<4 {
                ep[8 + i] = perm[i]
            }
        }
    }

    /// The coordinate representing permutation of the 8 non-slice edges
    /// (UR, UF, UL, UB, DR, DF, DL, DB).
    ///
    /// Used for phase 2 pruning and table lookups.
    public var edge8: Int {
        get {
            var edge8 = 0
            for j in stride(from: 7, through: 1, by: -1) {
                let s = ep[..<j].filter { $0 > ep[j] }.count
                edge8 = j * (edge8 + s)
            }
            return edge8
        }
        set {
            var edge8 = newValue
            var edges = Array(0..<8)
            var perm = [Int](repeating: 0, count: 8)
            var coeffs = [Int](repeating: 0, count: 7)
            for i in 1...7 {
                coeffs[i - 1] = edge8 % (i + 1)
                edge8 = edge8.floorDiv(by: i + 1)
            }
            for i in stride(from: 6, through: 0, by: -1) {
                perm[i + 1] = edges.remove(at: i + 1 - coeffs[i])
            }
            perm[0] = edges[0]
            for i in 0..<8 {
                ep[i] = TB2PEdge(rawValue: perm[i])!
            }
        }
    }

    /// The coordinate representing permutation of the 8 corners.
    ///
    /// Used for phase 2 pruning and table lookups.
    public var corner: Int {
        get {
            var c = 0
            for j in stride(from: 7, through: 1, by: -1) {
                let s = cp[..<j].filter { $0 > cp[j] }.count
                c = j * (c + s)
            }
            return c
        }
        set {
            var corn = newValue
            var corners = Array(0..<8)
            var perm = [Int](repeating: 0, count: 8)
            var coeffs = [Int](repeating: 0, count: 7)
            for i in 1...7 {
                coeffs[i - 1] = corn % (i + 1)
                corn = corn.floorDiv(by: i + 1)
            }
            for i in stride(from: 6, through: 0, by: -1) {
                perm[i + 1] = corners.remove(at: i + 1 - coeffs[i])
            }
            perm[0] = corners[0]
            for i in 0..<8 {
                cp[i] = TB2PCorner(rawValue: perm[i])!
            }
        }
    }

    /// The coordinate representing permutation of all 12 edges.
    ///
    /// Not used in solving, but needed for generating random cubes.
    public var edge: Int {
        get {
            var e = 0
            for j in stride(from: 11, through: 1, by: -1) {
                let s = ep[..<j].filter { $0 > ep[j] }.count
                e = j * (e + s)
            }
            return e
        }
        set {
            var edge = newValue
            var edges = Array(0..<12)
            var perm = [Int](repeating: 0, count: 12)
            var coeffs = [Int](repeating: 0, count: 11)
            for i in 1...11 {
                coeffs[i - 1] = edge % (i + 1)
                edge = edge.floorDiv(by: i + 1)
            }
            for i in stride(from: 10, through: 0, by: -1) {
                perm[i + 1] = edges.remove(at: i + 1 - coeffs[i])
            }
            perm[0] = edges[0]
            for i in 0..<12 {
                ep[i] = TB2PEdge(rawValue: perm[i])!
            }
        }
    }

    /// Verifies that the current cube state is valid and physically solvable.
    ///
    /// Checks that all edges and corners exist exactly once, orientations
    /// are valid, and parity matches. Throws an error if the cube is not
    /// solvable.
    public func verify() throws {
        // Edges
        var edgeCount = Array(repeating: 0, count: 12)
        for e in 0..<12 {
            edgeCount[ep[e]] += 1
        }
        guard edgeCount.allSatisfy({ $0 == 1 }) else {
            throw TB2PError.cubeVerificationFailed("not all edges exist exactly once")
        }
        if eo.reduce(0, +) % 2 != 0 {
            throw TB2PError.cubeVerificationFailed("one edge should be flipped")
        }
        // Corners
        var cornerCount = Array(repeating: 0, count: 8)
        for c in 0..<8 {
            cornerCount[cp[c]] += 1
        }
        guard cornerCount.allSatisfy({ $0 == 1 }) else {
            throw TB2PError.cubeVerificationFailed("not all corners exist exactly once")
        }
        if co.reduce(0, +) % 3 != 0 {
            throw TB2PError.cubeVerificationFailed("one corner should be twisted")
        }
        // Parity
        if self.edgeParity != self.cornerParity {
            throw TB2PError.cubeVerificationFailed("two corners or edges should be exchanged")
        }
    }

    // MARK: - Static moveCube array

    /// Precomputed CubieCube states for the six basic face moves (U, R, F,
    /// D, L, B), each representing a clockwise 90° turn.
    ///
    /// Used for efficient move application and cube manipulation.
    nonisolated(unsafe) static let moveCube: [TB2PCubieCube] = {

        let cpU: [TB2PCorner] = [.UBR, .URF, .UFL, .ULB, .DFR, .DLF, .DBL, .DRB]
        let coU: [Int] = [0, 0, 0, 0, 0, 0, 0, 0]
        let epU: [TB2PEdge] = [.UB, .UR, .UF, .UL, .DR, .DF, .DL, .DB, .FR, .FL, .BL, .BR]
        let eoU: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        let cpR: [TB2PCorner] = [.DFR, .UFL, .ULB, .URF, .DRB, .DLF, .DBL, .UBR]
        let coR: [Int] = [2, 0, 0, 1, 1, 0, 0, 2]
        let epR: [TB2PEdge] = [.FR, .UF, .UL, .UB, .BR, .DF, .DL, .DB, .DR, .FL, .BL, .UR]
        let eoR: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        let cpF: [TB2PCorner] = [.UFL, .DLF, .ULB, .UBR, .URF, .DFR, .DBL, .DRB]
        let coF: [Int] = [1, 2, 0, 0, 2, 1, 0, 0]
        let epF: [TB2PEdge] = [.UR, .FL, .UL, .UB, .DR, .FR, .DL, .DB, .UF, .DF, .BL, .BR]
        let eoF: [Int] = [0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0]

        let cpD: [TB2PCorner] = [.URF, .UFL, .ULB, .UBR, .DLF, .DBL, .DRB, .DFR]
        let coD: [Int] = [0, 0, 0, 0, 0, 0, 0, 0]
        let epD: [TB2PEdge] = [.UR, .UF, .UL, .UB, .DF, .DL, .DB, .DR, .FR, .FL, .BL, .BR]
        let eoD: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        let cpL: [TB2PCorner] = [.URF, .ULB, .DBL, .UBR, .DFR, .UFL, .DLF, .DRB]
        let coL: [Int] = [0, 1, 2, 0, 0, 2, 1, 0]
        let epL: [TB2PEdge] = [.UR, .UF, .BL, .UB, .DR, .DF, .FL, .DB, .FR, .UL, .DL, .BR]
        let eoL: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        let cpB: [TB2PCorner] = [.URF, .UFL, .UBR, .DRB, .DFR, .DLF, .ULB, .DBL]
        let coB: [Int] = [0, 0, 1, 2, 0, 0, 2, 1]
        let epB: [TB2PEdge] = [.UR, .UF, .UL, .BR, .DR, .DF, .DL, .BL, .FR, .FL, .UB, .DB]
        let eoB: [Int] = [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1]

        return [
            TB2PCubieCube(cp: cpU, co: coU, ep: epU, eo: eoU),
            TB2PCubieCube(cp: cpR, co: coR, ep: epR, eo: eoR),
            TB2PCubieCube(cp: cpF, co: coF, ep: epF, eo: eoF),
            TB2PCubieCube(cp: cpD, co: coD, ep: epD, eo: eoD),
            TB2PCubieCube(cp: cpL, co: coL, ep: epL, eo: eoL),
            TB2PCubieCube(cp: cpB, co: coB, ep: epB, eo: eoB),
        ]
    }()
}
// swiftlint: enable type_body_length

/// Computes the binomial coefficient (n choose k).
///
/// Returns the number of ways to choose k elements from n elements.
/// Used for coordinate encoding in the cube.
///
/// - Parameters:
///   - n: The total number of elements.
///   - k: The number of elements to choose.
/// - Returns: The binomial coefficient.
private func choose(_ n: Int, _ k: Int) -> Int {
    if 0 <= k && k <= n {
        var num = 1
        var den = 1
        var nVar = n
        let limit = min(k, n - k)
        if limit >= 1 {
            for i in 1...limit {
                num *= nVar
                den *= i
                nVar -= 1
            }
        }
        return num.floorDiv(by: den)
    } else {
        return 0
    }
}

/// Extension for Array<Int> to allow subscripting with enums.
extension Array where Element == Int {
    /// Accesses the element at the enum index.
    ///
    /// - Parameter index: Enum value with Int rawValue.
    /// - Returns: The element at the given index.
    fileprivate subscript<E: RawRepresentable>(_ index: E) -> Element where E.RawValue == Int {
        get {
            return self[index.rawValue]
        }
        set {
            self[index.rawValue] = newValue
        }
    }
}

/// Extension for Array<TB2PCorner> to allow subscripting with TB2PCorner.
extension Array where Element == TB2PCorner {
    /// Accesses the element at the TB2PCorner index.
    ///
    /// - Parameter corner: The TB2PCorner value.
    /// - Returns: The element at the given index.
    fileprivate subscript(_ corner: TB2PCorner) -> Element {
        get {
            precondition(count == TB2PCorner.allCases.count)
            return self[corner.rawValue]
        }
        set {
            precondition(count == TB2PCorner.allCases.count)
            self[corner.rawValue] = newValue
        }
    }
}

/// Extension for Array<TB2PEdge> to allow subscripting with TB2PEdge.
extension Array where Element == TB2PEdge {
    /// Accesses the element at the TB2PEdge index.
    ///
    /// - Parameter edge: The TB2PEdge value.
    /// - Returns: The element at the given index.
    fileprivate subscript(_ edge: TB2PEdge) -> Element {
        get {
            precondition(count == TB2PEdge.allCases.count)
            return self[edge.rawValue]
        }
        set {
            precondition(count == TB2PEdge.allCases.count)
            self[edge.rawValue] = newValue
        }
    }
}
