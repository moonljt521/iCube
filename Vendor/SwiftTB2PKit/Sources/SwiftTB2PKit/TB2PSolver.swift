// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

// swiftlint: disable file_length

import Foundation

/// Configuration for the TB2P cube solver.
///
/// Stores allowed solution length, timeout, and deadline for search.
struct TB2PSolverConfiguration {
    /// Maximum allowed solution length.
    var allowedLength: Int = 0

    /// Maximum allowed solving time in seconds.
    var timeout: TimeInterval = .infinity
    /// Absolute deadline timestamp for timeout.
    var deadline: Double

    /// Initializes the configuration with length and timeout.
    /// - Parameters:
    ///   - allowedLength: Maximum solution length.
    ///   - timeout: Maximum solving time in seconds.
    init(allowedLength: Int, timeout: TimeInterval) {
        self.allowedLength = allowedLength
        self.timeout = timeout
        self.deadline = CFAbsoluteTimeGetCurrent() + timeout
    }

    /// Returns true if the current time exceeds the deadline.
    var isTimedOut: Bool {
        CFAbsoluteTimeGetCurrent() > deadline
    }

}

// swiftlint: disable type_body_length
/// Two-phase Rubik's Cube solver using coordinate and pruning tables.
///
/// Provides methods to solve a cube from a facelet string using the Kociemba
/// two-phase algorithm. Supports timeouts and solution length limits.
public final class TB2PSolver {
    let facelets: String
    var faceCube: TB2PFaceCube!

    var axis: [Int] = []
    var power: [Int] = []
    var twist: [Int] = []
    var flip: [Int] = []
    var udslice: [Int] = []
    var corner: [Int] = []
    var edge4: [Int] = []
    var edge8: [Int] = []
    var minDist1: [Int] = []
    var minDist2: [Int] = []

    /// Initializes the solver with a facelet string.
    /// - Parameter facelets: The cube state as a facelet string.
    /// - Throws: TB2PError if the cube is invalid.
    public init(facelets: String) throws {
        self.facelets = facelets.uppercased()
        try verify()
    }

    /// Verifies the facelet string for correct colors and cube validity.
    /// - Throws: TB2PError if the cube is invalid.
    func verify() throws {
        var count = [Int](repeating: 0, count: 6)

        for char in facelets {
            guard let color = TB2PColor.from(character: char) else {
                throw TB2PError.cubeVerificationFailed("illegal color found")
            }
            count[color.rawValue] += 1
        }
        guard count.allSatisfy({ $0 == 9 }) else {
            throw TB2PError.cubeVerificationFailed("each color should appear exactly 9 times")
        }

        try TB2PFaceCube(cubeString: facelets).toCubieCube().verify()
    }

    /// Solves the cube using the two-phase algorithm.
    ///
    /// - Parameters:
    ///   - allowedLength: Maximum solution length (default: 25).
    ///   - timeout: Maximum solving time in seconds (default: 5).
    /// - Returns: Solution string or nil if not found.
    /// - Throws: TB2PError if solving fails or times out.
    public func search(allowedLength: Int = 25, timeout: TimeInterval = 5) throws -> String? {
        let configuration = TB2PSolverConfiguration(
            allowedLength: allowedLength,
            timeout: timeout
        )

        let tables = TB2P.tables

        try phase1Initialise(
            allowedLength: configuration.allowedLength,
            udsliceTwistPrune: tables.udsliceTwistPrune,
            udsliceFlipPrune: tables.udsliceFlipPrune,
        )

        for depth in 0..<configuration.allowedLength {
            let n = try phase1Search(
                n: 0,
                depth: depth,
                configuration: configuration,
                twistMove: tables.twistMove,
                flipMove: tables.flipMove,
                udsliceMove: tables.udsliceMove,
                edge4Move: tables.edge4Move,
                edge8Move: tables.edge8Move,
                cornerMove: tables.cornerMove,
                udsliceTwistPrune: tables.udsliceTwistPrune,
                udsliceFlipPrune: tables.udsliceFlipPrune,
                edge4CornerPrune: tables.edge4CornerPrune,
                edge4Edge8Prune: tables.edge4Edge8Prune,
            )
            if n >= 0 {
                return solutionToString(length: n)
            }
        }

        return nil
    }

    /// Finds the shortest solution within the given timeout.
    ///
    /// - Parameter timeout: Maximum solving time in seconds (default: 5).
    /// - Returns: Shortest solution string or nil if not found.
    public func searchBest(timeout: TimeInterval = 5) throws -> String? {
        var allowedLength = 25
        var timeout = timeout
        var solution: String?
        while timeout > 0 {
            let start = CFAbsoluteTimeGetCurrent()
            if let newSolution = try? search(allowedLength: allowedLength, timeout: timeout) {
                solution = newSolution
            }
            allowedLength -= 1
            timeout -= CFAbsoluteTimeGetCurrent() - start
        }
        return solution
    }

    /// Converts the internal move sequence to a human-readable string.
    /// - Parameter length: Number of moves in the solution.
    /// - Returns: Solution string in standard notation.
    private func solutionToString(length: Int) -> String {
        func recoverMove(axis: Int, power: Int) -> String {
            let faces = ["U", "R", "F", "D", "L", "B"]
            switch power {
            case 1: return faces[axis]
            case 2: return faces[axis] + "2"
            case 3: return faces[axis] + "'"
            default: return "?"
            }
        }
        let moves = (0..<length).map { recoverMove(axis: axis[$0], power: power[$0]) }
        return moves.joined(separator: " ")
    }

    // MARK: - Phase 1 Init

    /// Initializes phase 1 search coordinates and arrays.
    /// - Parameters:
    ///   - allowedLength: Maximum solution length.
    ///   - udsliceTwistPrune: Pruning table for UDSlice/Twist.
    ///   - udsliceFlipPrune: Pruning table for UDSlice/Flip.
    /// - Throws: TB2PError if cube is invalid.
    func phase1Initialise(
        allowedLength: Int,
        udsliceTwistPrune: TB2PPruningTable,
        udsliceFlipPrune: TB2PPruningTable,
    ) throws {
        faceCube = try TB2PFaceCube(cubeString: facelets)

        axis = [Int](repeating: 0, count: allowedLength)
        power = [Int](repeating: 0, count: allowedLength)
        twist = [Int](repeating: 0, count: allowedLength)
        flip = [Int](repeating: 0, count: allowedLength)
        udslice = [Int](repeating: 0, count: allowedLength)
        corner = [Int](repeating: 0, count: allowedLength)
        edge4 = [Int](repeating: 0, count: allowedLength)
        edge8 = [Int](repeating: 0, count: allowedLength)
        minDist1 = [Int](repeating: 0, count: allowedLength)
        minDist2 = [Int](repeating: 0, count: allowedLength)

        let coordCube = TB2PCoordCube.fromCubieCube(faceCube.toCubieCube())
        twist[0] = coordCube.twist
        flip[0] = coordCube.flip
        udslice[0] = coordCube.udslice
        corner[0] = coordCube.corner
        edge4[0] = coordCube.edge4
        edge8[0] = coordCube.edge8
        minDist1[0] = phase1Cost(
            n: 0,
            udsliceTwistPrune: udsliceTwistPrune,
            udsliceFlipPrune: udsliceFlipPrune,
        )
    }

    // MARK: - Phase 1 Search

    // swiftlint: disable function_body_length function_parameter_count
    /// Recursively searches for phase 1 solutions up to given depth.
    /// - Parameters: Search state, tables, pruning tables.
    /// - Returns: Solution length or -1 if not found.
    /// - Throws: TB2PError if timeout occurs.
    func phase1Search(
        n: Int,
        depth: Int,
        configuration: TB2PSolverConfiguration,
        twistMove: TP2PInteger2D,
        flipMove: TP2PInteger2D,
        udsliceMove: TP2PInteger2D,
        edge4Move: TP2PInteger2D,
        edge8Move: TP2PInteger2D,
        cornerMove: TP2PInteger2D,
        udsliceTwistPrune: TB2PPruningTable,
        udsliceFlipPrune: TB2PPruningTable,
        edge4CornerPrune: TB2PPruningTable,
        edge4Edge8Prune: TB2PPruningTable,
    ) throws -> Int {
        guard !configuration.isTimedOut else {
            throw TB2PError.cubeSolvingTimeout
        }

        if minDist1[n] == 0 {
            return try phase2Initialise(
                n: n,
                configuration: configuration,
                edge4Move: edge4Move,
                edge8Move: edge8Move,
                cornerMove: cornerMove,
                udsliceTwistPrune: udsliceTwistPrune,
                udsliceFlipPrune: udsliceFlipPrune,
                edge4CornerPrune: edge4CornerPrune,
                edge4Edge8Prune: edge4Edge8Prune,
            )

        }

        if minDist1[n] > depth {
            return -1
        }

        for face in 0..<6 {
            if n > 0 && (axis[n - 1] == face || axis[n - 1] == face + 3) {
                continue
            }
            for j in 1...3 {
                let move = 3 * face + j - 1
                axis[n] = face
                power[n] = j
                twist[n + 1] = twistMove[twist[n]][move]
                flip[n + 1] = flipMove[flip[n]][move]
                udslice[n + 1] = udsliceMove[udslice[n]][move]
                minDist1[n + 1] = enhancedPhase1Cost(
                    n: n + 1,
                    udsliceTwistPrune: udsliceTwistPrune,
                    udsliceFlipPrune: udsliceFlipPrune,
                )
                if minDist1[n + 1] <= depth - 1 {
                    let m = try phase1Search(
                        n: n + 1,
                        depth: depth - 1,
                        configuration: configuration,
                        twistMove: twistMove,
                        flipMove: flipMove,
                        udsliceMove: udsliceMove,
                        edge4Move: edge4Move,
                        edge8Move: edge8Move,
                        cornerMove: cornerMove,
                        udsliceTwistPrune: udsliceTwistPrune,
                        udsliceFlipPrune: udsliceFlipPrune,
                        edge4CornerPrune: edge4CornerPrune,
                        edge4Edge8Prune: edge4Edge8Prune,
                    )
                    if m >= 0 {
                        return m
                    }
                }
            }
        }

        return -1
    }
    // swiftlint: enable function_body_length function_parameter_count

    // MARK: - Phase 2 Init

    // swiftlint: disable function_parameter_count
    /// Initializes phase 2 search coordinates and arrays.
    /// - Parameters: Search state, tables, pruning tables.
    /// - Returns: Solution length or -1 if not found.
    /// - Throws: TB2PError if timeout occurs.
    func phase2Initialise(
        n: Int,
        configuration: TB2PSolverConfiguration,
        edge4Move: TP2PInteger2D,
        edge8Move: TP2PInteger2D,
        cornerMove: TP2PInteger2D,
        udsliceTwistPrune: TB2PPruningTable,
        udsliceFlipPrune: TB2PPruningTable,
        edge4CornerPrune: TB2PPruningTable,
        edge4Edge8Prune: TB2PPruningTable,
    ) throws -> Int {
        guard !configuration.isTimedOut else {
            throw TB2PError.cubeSolvingTimeout
        }

        let cubieCube = faceCube.toCubieCube()
        for i in 0..<n {
            for _ in 0..<power[i] {
                cubieCube.move(axis[i])
            }
        }
        edge4[n] = cubieCube.edge4
        edge8[n] = cubieCube.edge8
        corner[n] = cubieCube.corner
        minDist2[n] = phase2Cost(
            n: n,
            edge4CornerPrune: edge4CornerPrune,
            edge4Edge8Prune: edge4Edge8Prune,
        )
        for depth in 0..<(configuration.allowedLength - n) {
            let m = phase2Search(
                n: n,
                depth: depth,
                edge4Move: edge4Move,
                edge8Move: edge8Move,
                cornerMove: cornerMove,
                udsliceTwistPrune: udsliceTwistPrune,
                udsliceFlipPrune: udsliceFlipPrune,
                edge4CornerPrune: edge4CornerPrune,
                edge4Edge8Prune: edge4Edge8Prune,
            )
            if m >= 0 {
                return m
            }
        }
        return -1
    }
    // swiftlint: enable function_parameter_count

    // MARK: - Phase 2 Search

    // swiftlint: disable function_parameter_count
    /// Recursively searches for phase 2 solutions up to given depth.
    /// - Parameters: Search state, tables, pruning tables.
    /// - Returns: Solution length or -1 if not found.
    func phase2Search(
        n: Int,
        depth: Int,
        edge4Move: TP2PInteger2D,
        edge8Move: TP2PInteger2D,
        cornerMove: TP2PInteger2D,
        udsliceTwistPrune: TB2PPruningTable,
        udsliceFlipPrune: TB2PPruningTable,
        edge4CornerPrune: TB2PPruningTable,
        edge4Edge8Prune: TB2PPruningTable,
    ) -> Int {
        if minDist2[n] == 0 {
            return n
        } else if minDist2[n] <= depth {
            for i in 0..<6 {
                if n > 0 && (axis[n - 1] == i || axis[n - 1] == i + 3) {
                    continue
                }
                for j in 1...3 {
                    if [1, 2, 4, 5].contains(i) && j != 2 {
                        continue
                    }
                    axis[n] = i
                    power[n] = j
                    let move = 3 * i + j - 1
                    edge4[n + 1] = edge4Move[edge4[n]][move]
                    edge8[n + 1] = edge8Move[edge8[n]][move]
                    corner[n + 1] = cornerMove[corner[n]][move]
                    minDist2[n + 1] = phase2Cost(
                        n: n + 1,
                        edge4CornerPrune: edge4CornerPrune,
                        edge4Edge8Prune: edge4Edge8Prune,
                    )
                    let m = phase2Search(
                        n: n + 1,
                        depth: depth - 1,
                        edge4Move: edge4Move,
                        edge8Move: edge8Move,
                        cornerMove: cornerMove,
                        udsliceTwistPrune: udsliceTwistPrune,
                        udsliceFlipPrune: udsliceFlipPrune,
                        edge4CornerPrune: edge4CornerPrune,
                        edge4Edge8Prune: edge4Edge8Prune,
                    )
                    if m >= 0 {
                        return m
                    }
                }
            }
        }
        return -1
    }
    // swiftlint: enable function_parameter_count

    // MARK: - Cost Functions

    /// Computes the phase 1 cost (lower bound) for current state.
    /// - Parameters: Search state, pruning tables.
    /// - Returns: Lower bound on moves to solve phase 1.
    @inline(__always)
    func phase1Cost(
        n: Int,
        udsliceTwistPrune: TB2PPruningTable,
        udsliceFlipPrune: TB2PPruningTable,
    ) -> Int {
        max(
            udsliceTwistPrune[(udslice[n], twist[n])],
            udsliceFlipPrune[(udslice[n], flip[n])]
        )
    }

    /// Computes the enhanced phase 1 cost for current state.
    /// - Parameters: Search state, pruning tables.
    /// - Returns: Lower bound on moves to solve phase 1.
    @inline(__always)
    func enhancedPhase1Cost(
        n: Int,
        udsliceTwistPrune: TB2PPruningTable,
        udsliceFlipPrune: TB2PPruningTable,
    ) -> Int {
        let twistCost = udsliceTwistPrune[(udslice[n], twist[n])]
        let flipCost = udsliceFlipPrune[(udslice[n], flip[n])]

        let baseCost = max(twistCost, flipCost)

        if twist[n] == 0 && flip[n] == 0 && udslice[n] != 0 {
            return baseCost + 1
        }

        return baseCost
    }

    /// Computes the phase 2 cost (lower bound) for current state.
    /// - Parameters: Search state, pruning tables.
    /// - Returns: Lower bound on moves to solve phase 2.
    @inline(__always)
    func phase2Cost(
        n: Int,
        edge4CornerPrune: TB2PPruningTable,
        edge4Edge8Prune: TB2PPruningTable,
    ) -> Int {
        max(
            edge4CornerPrune[(edge4[n], corner[n])],
            edge4Edge8Prune[(edge4[n], edge8[n])]
        )
    }
}
// swiftlint: enable type_body_length
