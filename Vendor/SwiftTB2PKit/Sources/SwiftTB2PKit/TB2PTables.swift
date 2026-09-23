// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

// swiftlint: disable file_length

import Foundation

typealias TP2PInteger2D = ContiguousArray<ContiguousArray<Int>>

public struct TB2PPruningTable: Equatable, Sendable {
    /// The flat table data.
    let table: [Int]
    /// The stride (row length) for 2D access.
    let stride: Int

    public static func == (lhs: TB2PPruningTable, rhs: TB2PPruningTable) -> Bool {
        lhs.stride == rhs.stride && lhs.table == rhs.table
    }

    /// Accesses the table at the given coordinate.
    /// - Parameter coord: Tuple (row, column).
    subscript(coord: (Int, Int)) -> Int {
        return table[coord.0 * stride + coord.1]
    }
}

// swiftlint: disable type_body_length
/// Holds all move and pruning tables for the two-phase solver.
///
/// Provides methods to load, save, and generate tables. Move tables are used
/// to update the coordinate representation of the cube when a move is applied.
/// Pruning tables provide lower bounds for the number of moves to solve.
public final class TB2PTables: Equatable, Sendable {
    static let TWIST = 2187  // 3^7 possible corner orientations
    static let FLIP = 2048  // 2^11 possible edge flips
    static let UDSLICE = 495  // 12C4 possible positions of the slice edges
    static let EDGE4 = 24  // 4! permutations of the slice edges
    static let EDGE8 = 40320  // 8! permutations of the remaining edges
    static let CORNER = 40320  // 8! permutations of the corners
    static let EDGE = 479_001_600  // 12! permutations of all edges
    static let MOVES = 18  // 6*3 possible moves

    /// Move table for corner orientation (twist).
    let twistMove: TP2PInteger2D
    /// Move table for edge orientation (flip).
    let flipMove: TP2PInteger2D
    /// Move table for UDSlice position.
    let udsliceMove: TP2PInteger2D
    /// Move table for 4-slice edge permutation.
    let edge4Move: TP2PInteger2D
    /// Move table for 8 non-slice edge permutation.
    let edge8Move: TP2PInteger2D
    /// Move table for corner permutation.
    let cornerMove: TP2PInteger2D
    /// Pruning table for UDSlice and twist.
    let udsliceTwistPrune: TB2PPruningTable
    /// Pruning table for UDSlice and flip.
    let udsliceFlipPrune: TB2PPruningTable
    /// Pruning table for edge4 and edge8.
    let edge4Edge8Prune: TB2PPruningTable
    /// Pruning table for edge4 and corner.
    let edge4CornerPrune: TB2PPruningTable

    init(
        twistMove: TP2PInteger2D,
        flipMove: TP2PInteger2D,
        udsliceMove: TP2PInteger2D,
        edge4Move: TP2PInteger2D,
        edge8Move: TP2PInteger2D,
        cornerMove: TP2PInteger2D,
        udsliceTwistPrune: TB2PPruningTable,
        udsliceFlipPrune: TB2PPruningTable,
        edge4Edge8Prune: TB2PPruningTable,
        edge4CornerPrune: TB2PPruningTable
    ) {
        self.twistMove = twistMove
        self.flipMove = flipMove
        self.udsliceMove = udsliceMove
        self.edge4Move = edge4Move
        self.edge8Move = edge8Move
        self.cornerMove = cornerMove
        self.udsliceTwistPrune = udsliceTwistPrune
        self.udsliceFlipPrune = udsliceFlipPrune
        self.edge4Edge8Prune = edge4Edge8Prune
        self.edge4CornerPrune = edge4CornerPrune
    }

    public static func == (lhs: TB2PTables, rhs: TB2PTables) -> Bool {
        return lhs.twistMove == rhs.twistMove && lhs.flipMove == rhs.flipMove
            && lhs.udsliceMove == rhs.udsliceMove && lhs.edge4Move == rhs.edge4Move
            && lhs.edge8Move == rhs.edge8Move && lhs.cornerMove == rhs.cornerMove
            && lhs.udsliceTwistPrune == rhs.udsliceTwistPrune
            && lhs.udsliceFlipPrune == rhs.udsliceFlipPrune && lhs.edge4Edge8Prune == rhs.edge4Edge8Prune
            && lhs.edge4CornerPrune == rhs.edge4CornerPrune
    }

    /// Returns the URL for the JSON tables file.
    static var jsonFileURL: URL {
        let fileManager = FileManager.default
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let tablesURL = cachesURL.appendingPathComponent("TB2PTables.json")
        return tablesURL
    }

    /// Returns the URL for the binary tables file.
    static var binFileURL: URL {
        let fileManager = FileManager.default
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let tablesURL = cachesURL.appendingPathComponent("TB2PTables.bin")
        return tablesURL
    }

    /// Loads all tables from JSON file or generates and saves them if missing.
    public static func loadFromJSON() throws -> TB2PTables {
        let jsonFileURL = Self.jsonFileURL
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: jsonFileURL.path) {
            return try loadJSON(from: jsonFileURL)
        } else {
            let tables = make()
            try save(asJSON: tables, to: jsonFileURL)
            return tables
        }
    }

    /// Loads all tables from binary file or generates and saves them if missing.
    public static func loadFromBinary() throws -> TB2PTables {
        let binFileURL = Self.binFileURL
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: binFileURL.path) {
            return try loadBinary(from: binFileURL)
        } else {
            let tables = make()
            try save(asBinary: tables, to: binFileURL)
            return tables
        }
    }

    /// Generates all move and pruning tables in memory.
    internal static func make() -> TB2PTables {
        let twistMove = ContiguousArray(makeTwistTable().map(ContiguousArray.init))
        let flipMove = ContiguousArray(makeFlipTable().map(ContiguousArray.init))
        let udsliceMove = ContiguousArray(makeUdsliceTable().map(ContiguousArray.init))
        let edge4Move = ContiguousArray(makeEdge4Table().map(ContiguousArray.init))
        let edge8Move = ContiguousArray(makeEdge8Table().map(ContiguousArray.init))
        let cornerMove = ContiguousArray(makeCornerTable().map(ContiguousArray.init))
        let udsliceTwistPrune = makeUdsliceTwistPrune(twistMove: twistMove, udsliceMove: udsliceMove)
        let udsliceFlipPrune = makeUdsliceFlipPrune(flipMove: flipMove, udsliceMove: udsliceMove)
        let edge4Edge8Prune = makeEdge4Edge8Prune(edge4Move: edge4Move, edge8Move: edge8Move)
        let edge4CornerPrune = makeEdge4CornerPrune(cornerMove: cornerMove, edge4Move: edge4Move)
        return .init(
            twistMove: twistMove,
            flipMove: flipMove,
            udsliceMove: udsliceMove,
            edge4Move: edge4Move,
            edge8Move: edge8Move,
            cornerMove: cornerMove,
            udsliceTwistPrune: udsliceTwistPrune,
            udsliceFlipPrune: udsliceFlipPrune,
            edge4Edge8Prune: edge4Edge8Prune,
            edge4CornerPrune: edge4CornerPrune,
        )
    }

    // MARK: - JSON

    /// Loads tables from a JSON file at the given URL.
    /// - Parameter url: The file URL to load from.
    internal static func loadJSON(from url: URL) throws -> TB2PTables {
        do {
            let data = try Data(contentsOf: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let twistMoveArray = json["twist_move"] as? [[Int]] ?? []
                let flipMoveArray = json["flip_move"] as? [[Int]] ?? []
                let udsliceMoveArray = json["udslice_move"] as? [[Int]] ?? []
                let edge4MoveArray = json["edge4_move"] as? [[Int]] ?? []
                let edge8MoveArray = json["edge8_move"] as? [[Int]] ?? []
                let cornerMoveArray = json["corner_move"] as? [[Int]] ?? []
                guard let udsliceTwistPruneArr = json["udslice_twist_prune"] as? [Int] else {
                    throw TB2PError.tablesJSONLoadInvalidData
                }
                guard let udsliceFlipPruneArr = json["udslice_flip_prune"] as? [Int] else {
                    throw TB2PError.tablesJSONLoadInvalidData
                }
                guard let edge4Edge8PruneArr = json["edge4_edge8_prune"] as? [Int] else {
                    throw TB2PError.tablesJSONLoadInvalidData
                }
                guard let edge4CornerPruneArr = json["edge4_corner_prune"] as? [Int] else {
                    throw TB2PError.tablesJSONLoadInvalidData
                }
                return .init(
                    twistMove: ContiguousArray(twistMoveArray.map(ContiguousArray.init)),
                    flipMove: ContiguousArray(flipMoveArray.map(ContiguousArray.init)),
                    udsliceMove: ContiguousArray(udsliceMoveArray.map(ContiguousArray.init)),
                    edge4Move: ContiguousArray(edge4MoveArray.map(ContiguousArray.init)),
                    edge8Move: ContiguousArray(edge8MoveArray.map(ContiguousArray.init)),
                    cornerMove: ContiguousArray(cornerMoveArray.map(ContiguousArray.init)),
                    udsliceTwistPrune: TB2PPruningTable(table: udsliceTwistPruneArr, stride: Self.TWIST),
                    udsliceFlipPrune: TB2PPruningTable(table: udsliceFlipPruneArr, stride: Self.FLIP),
                    edge4Edge8Prune: TB2PPruningTable(table: edge4Edge8PruneArr, stride: Self.EDGE8),
                    edge4CornerPrune: TB2PPruningTable(table: edge4CornerPruneArr, stride: Self.CORNER),
                )
            } else {
                throw TB2PError.tablesJSONLoadInvalidData
            }
        } catch {
            throw TB2PError.tablesJSONLoadFailed(error: error)
        }
    }

    /// Saves tables to a JSON file at the given URL.
    /// - Parameter url: The file URL to save to.
    internal static func save(asJSON tables: TB2PTables, to url: URL) throws {
        let tables: [String: Any] = [
            "twist_move": tables.twistMove.map(Array.init),
            "flip_move": tables.flipMove.map(Array.init),
            "udslice_move": tables.udsliceMove.map(Array.init),
            "edge4_move": tables.edge4Move.map(Array.init),
            "edge8_move": tables.edge8Move.map(Array.init),
            "corner_move": tables.cornerMove.map(Array.init),
            "udslice_twist_prune": tables.udsliceTwistPrune.table,
            "udslice_flip_prune": tables.udsliceFlipPrune.table,
            "edge4_edge8_prune": tables.edge4Edge8Prune.table,
            "edge4_corner_prune": tables.edge4CornerPrune.table,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: tables, options: [])
            try data.write(to: url)
        } catch {
            throw TB2PError.tablesJSONSaveFailed(error: error)
        }
    }

    // MARK: - Binary

    // swiftlint: disable function_body_length
    /// Loads tables from a binary file at the given URL.
    /// - Parameter url: The file URL to load from.
    internal static func loadBinary(from url: URL) throws -> TB2PTables {
        do {
            let data = try Data(contentsOf: url)
            var offset = 0

            @inline(__always)
            func readInt32() -> Int32 {
                let value = data.withUnsafeBytes {
                    $0.load(fromByteOffset: offset, as: Int32.self)
                }
                offset += MemoryLayout<Int32>.size
                return value
            }

            @inline(__always)
            func readArray2D(_ rows: Int, _ cols: Int) -> [[Int]] {
                var arr = [[Int]]()
                arr.reserveCapacity(rows)
                for _ in 0..<rows {
                    var row = [Int]()
                    row.reserveCapacity(cols)
                    for _ in 0..<cols {
                        row.append(Int(readInt32()))
                    }
                    arr.append(row)
                }
                return arr
            }

            @inline(__always)
            func readArray1D(_ count: Int) -> [Int] {
                var arr = [Int]()
                arr.reserveCapacity(count)
                for _ in 0..<count {
                    arr.append(Int(readInt32()))
                }
                return arr
            }

            let twistMoveArray = readArray2D(Self.TWIST, Self.MOVES)
            let flipMoveArray = readArray2D(Self.FLIP, Self.MOVES)
            let udsliceMoveArray = readArray2D(Self.UDSLICE, Self.MOVES)
            let edge4MoveArray = readArray2D(Self.EDGE4, Self.MOVES)
            let edge8MoveArray = readArray2D(Self.EDGE8, Self.MOVES)
            let cornerMoveArray = readArray2D(Self.CORNER, Self.MOVES)
            let udsliceTwistPrune = TB2PPruningTable(
                table: readArray1D(Self.UDSLICE * Self.TWIST), stride: Self.TWIST)
            let udsliceFlipPrune = TB2PPruningTable(
                table: readArray1D(Self.UDSLICE * Self.FLIP), stride: Self.FLIP)
            let edge4Edge8Prune = TB2PPruningTable(
                table: readArray1D(Self.EDGE4 * Self.EDGE8), stride: Self.EDGE8)
            let edge4CornerPrune = TB2PPruningTable(
                table: readArray1D(Self.EDGE4 * Self.CORNER), stride: Self.CORNER)
            return .init(
                twistMove: ContiguousArray(twistMoveArray.map(ContiguousArray.init)),
                flipMove: ContiguousArray(flipMoveArray.map(ContiguousArray.init)),
                udsliceMove: ContiguousArray(udsliceMoveArray.map(ContiguousArray.init)),
                edge4Move: ContiguousArray(edge4MoveArray.map(ContiguousArray.init)),
                edge8Move: ContiguousArray(edge8MoveArray.map(ContiguousArray.init)),
                cornerMove: ContiguousArray(cornerMoveArray.map(ContiguousArray.init)),
                udsliceTwistPrune: udsliceTwistPrune,
                udsliceFlipPrune: udsliceFlipPrune,
                edge4Edge8Prune: edge4Edge8Prune,
                edge4CornerPrune: edge4CornerPrune,
            )
        } catch {
            throw TB2PError.tablesBinaryLoadFailed(error: error)
        }
    }
    // swiftlint: enable function_body_length

    /// Saves tables to a binary file at the given URL.
    /// - Parameter url: The file URL to save to.
    internal static func save(asBinary tables: TB2PTables, to url: URL) throws {
        var data = Data(capacity: 64_000_000)

        @inline(__always)
        func appendArray2D(_ arr: [[Int]]) {
            for row in arr {
                for value in row {
                    let v = Int32(value)
                    withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
                }
            }
        }
        @inline(__always)
        func appendArray1D(_ arr: [Int]) {
            for value in arr {
                let v = Int32(value)
                withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
            }
        }
        appendArray2D(tables.twistMove.map(Array.init))
        appendArray2D(tables.flipMove.map(Array.init))
        appendArray2D(tables.udsliceMove.map(Array.init))
        appendArray2D(tables.edge4Move.map(Array.init))
        appendArray2D(tables.edge8Move.map(Array.init))
        appendArray2D(tables.cornerMove.map(Array.init))
        appendArray1D(tables.udsliceTwistPrune.table)
        appendArray1D(tables.udsliceFlipPrune.table)
        appendArray1D(tables.edge4Edge8Prune.table)
        appendArray1D(tables.edge4CornerPrune.table)
        do {
            try data.write(to: url)
        } catch {
            throw TB2PError.tablesBinarySaveFailed(error: error)
        }
    }

    // MARK: - Tables

    /// Generates the twist move table.
    /// - Returns: The twist move table as a 2D array.
    private static func makeTwistTable() -> [[Int]] {
        var twistMove = Array(repeating: Array(repeating: 0, count: Self.MOVES), count: Self.TWIST)
        let a = TB2PCubieCube()
        for i in 0..<Self.TWIST {
            a.twist = i
            for j in 0..<6 {
                for k in 0..<3 {
                    a.cornerMultiply(TB2PCubieCube.moveCube[j])
                    twistMove[i][3 * j + k] = a.twist
                }
                a.cornerMultiply(TB2PCubieCube.moveCube[j])
            }
        }
        return twistMove
    }

    /// Generates the flip move table.
    /// - Returns: The flip move table as a 2D array.
    private static func makeFlipTable() -> [[Int]] {
        var flipMove = Array(repeating: Array(repeating: 0, count: Self.MOVES), count: Self.FLIP)
        let a = TB2PCubieCube()
        for i in 0..<Self.FLIP {
            a.flip = i
            for j in 0..<6 {
                for k in 0..<3 {
                    a.edgeMultiply(TB2PCubieCube.moveCube[j])
                    flipMove[i][3 * j + k] = a.flip
                }
                a.edgeMultiply(TB2PCubieCube.moveCube[j])
            }
        }
        return flipMove
    }

    /// Generates the UDSlice move table.
    /// - Returns: The UDSlice move table as a 2D array.
    private static func makeUdsliceTable() -> [[Int]] {
        var udsliceMove = Array(repeating: Array(repeating: 0, count: Self.MOVES), count: Self.UDSLICE)
        let a = TB2PCubieCube()
        for i in 0..<Self.UDSLICE {
            a.udslice = i
            for j in 0..<6 {
                for k in 0..<3 {
                    a.edgeMultiply(TB2PCubieCube.moveCube[j])
                    udsliceMove[i][3 * j + k] = a.udslice
                }
                a.edgeMultiply(TB2PCubieCube.moveCube[j])
            }
        }
        return udsliceMove
    }

    /// Generates the edge4 move table.
    /// - Returns: The edge4 move table as a 2D array.
    private static func makeEdge4Table() -> [[Int]] {
        var edge4Move = Array(repeating: Array(repeating: 0, count: Self.MOVES), count: Self.EDGE4)
        let a = TB2PCubieCube()
        for i in 0..<Self.EDGE4 {
            a.edge4 = i
            for j in 0..<6 {
                for k in 0..<3 {
                    a.edgeMultiply(TB2PCubieCube.moveCube[j])
                    if k % 2 == 0 && j % 3 != 0 {
                        edge4Move[i][3 * j + k] = -1
                    } else {
                        edge4Move[i][3 * j + k] = a.edge4
                    }
                }
                a.edgeMultiply(TB2PCubieCube.moveCube[j])
            }
        }
        return edge4Move
    }

    /// Generates the edge8 move table.
    /// - Returns: The edge8 move table as a 2D array.
    private static func makeEdge8Table() -> [[Int]] {
        var edge8Move = Array(repeating: Array(repeating: 0, count: Self.MOVES), count: Self.EDGE8)
        let a = TB2PCubieCube()
        for i in 0..<Self.EDGE8 {
            a.edge8 = i
            for j in 0..<6 {
                for k in 0..<3 {
                    a.edgeMultiply(TB2PCubieCube.moveCube[j])
                    if k % 2 == 0 && j % 3 != 0 {
                        edge8Move[i][3 * j + k] = -1
                    } else {
                        edge8Move[i][3 * j + k] = a.edge8
                    }
                }
                a.edgeMultiply(TB2PCubieCube.moveCube[j])
            }
        }
        return edge8Move
    }

    /// Generates the corner move table.
    /// - Returns: The corner move table as a 2D array.
    private static func makeCornerTable() -> [[Int]] {
        var cornerMove = Array(
            repeating: Array(
                repeating: 0,
                count: Self.MOVES
            ),
            count: Self.CORNER
        )
        let a = TB2PCubieCube()
        for i in 0..<Self.CORNER {
            a.corner = i
            for j in 0..<6 {
                for k in 0..<3 {
                    a.cornerMultiply(TB2PCubieCube.moveCube[j])
                    if k % 2 == 0 && j % 3 != 0 {
                        cornerMove[i][3 * j + k] = -1
                    } else {
                        cornerMove[i][3 * j + k] = a.corner
                    }
                }
                a.cornerMultiply(TB2PCubieCube.moveCube[j])
            }
        }
        return cornerMove
    }

    /// Generates the UDSlice-Twist pruning table.
    /// - Returns: The pruning table for UDSlice and twist.
    private static func makeUdsliceTwistPrune(
        twistMove: TP2PInteger2D,
        udsliceMove: TP2PInteger2D
    ) -> TB2PPruningTable {
        var table = Array(repeating: -1, count: Self.UDSLICE * Self.TWIST)
        table[0] = 0
        var count = 1
        var depth = 0
        while count < Self.UDSLICE * Self.TWIST {
            for i in 0..<(Self.UDSLICE * Self.TWIST) where table[i] == depth {
                let m = (0..<18).map { j in
                    udsliceMove[i.floorDiv(by: Self.TWIST)][j] * Self.TWIST
                        + twistMove[i % Self.TWIST][j]
                }
                for j in m where table[j] == -1 {
                    count += 1
                    table[j] = depth + 1
                }
            }
            depth += 1
        }
        return TB2PPruningTable(table: table, stride: Self.TWIST)
    }

    /// Generates the UDSlice-Flip pruning table.
    /// - Returns: The pruning table for UDSlice and flip.
    private static func makeUdsliceFlipPrune(
        flipMove: TP2PInteger2D,
        udsliceMove: TP2PInteger2D,
    ) -> TB2PPruningTable {
        var table = Array(repeating: -1, count: Self.UDSLICE * Self.FLIP)
        table[0] = 0
        var count = 1
        var depth = 0
        while count < Self.UDSLICE * Self.FLIP {
            for i in 0..<(Self.UDSLICE * Self.FLIP) where table[i] == depth {
                let m = (0..<18).map { j in
                    udsliceMove[i.floorDiv(by: Self.FLIP)][j] * Self.FLIP
                        + flipMove[i % Self.FLIP][j]
                }
                for j in m where table[j] == -1 {
                    count += 1
                    table[j] = depth + 1
                }
            }
            depth += 1
        }
        return TB2PPruningTable(table: table, stride: Self.FLIP)
    }

    /// Generates the Edge4-Edge8 pruning table.
    /// - Returns: The pruning table for edge4 and edge8.
    private static func makeEdge4Edge8Prune(
        edge4Move: TP2PInteger2D,
        edge8Move: TP2PInteger2D,
    ) -> TB2PPruningTable {
        var table = Array(repeating: -1, count: Self.EDGE4 * Self.EDGE8)
        table[0] = 0
        var count = 1
        var depth = 0
        while count < Self.EDGE4 * Self.EDGE8 {
            for i in 0..<(Self.EDGE4 * Self.EDGE8) where table[i] == depth {
                let m = (0..<18).map { j in
                    edge4Move[i.floorDiv(by: Self.EDGE8)][j] * Self.EDGE8
                        + edge8Move[i % Self.EDGE8][j]
                }
                for j in m where table[wrapped: j] == -1 {
                    count += 1
                    table[wrapped: j] = depth + 1
                }
            }
            depth += 1
        }
        return TB2PPruningTable(table: table, stride: Self.EDGE8)
    }

    /// Generates the Edge4-Corner pruning table.
    /// - Returns: The pruning table for edge4 and corner.
    private static func makeEdge4CornerPrune(
        cornerMove: TP2PInteger2D,
        edge4Move: TP2PInteger2D,
    ) -> TB2PPruningTable {
        var table = Array(repeating: -1, count: Self.EDGE4 * Self.CORNER)
        table[0] = 0
        var count = 1
        var depth = 0
        while count < Self.EDGE4 * Self.CORNER {
            for i in 0..<(Self.EDGE4 * Self.CORNER) where table[i] == depth {
                let m = (0..<18).map { j in
                    edge4Move[i.floorDiv(by: Self.CORNER)][j] * Self.CORNER
                        + cornerMove[i % Self.CORNER][j]
                }
                for j in m where table[wrapped: j] == -1 {
                    count += 1
                    table[wrapped: j] = depth + 1
                }
            }
            depth += 1
        }
        return TB2PPruningTable(table: table, stride: Self.CORNER)
    }
}
// swiftlint: enable type_body_length
