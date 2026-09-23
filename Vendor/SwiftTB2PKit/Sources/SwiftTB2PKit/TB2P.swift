// TwistAssist | Michael Baumgärtner | © 2025 | All rights reserved | MIT License

// Inspiration was taken from
//   https://github.com/tcbegley/cube-solver - MIT License.
// No source code was copied.

import Foundation
import os

public enum TB2P {
    /// Generates a random, valid cube state as a string representation.
    ///
    /// The generated cube state is guaranteed to have matching edge and corner
    /// parity, ensuring it is a physically possible configuration. The function
    /// randomly assigns flip, twist, corner, and edge values within their valid
    /// ranges, and repeats the process until a valid parity is achieved.
    ///
    /// - Returns: A string describing the random cube state in facelet notation.
    public static func randomCube() -> String {
        let flip = Int.random(in: 0..<TB2PTables.FLIP)
        let twist = Int.random(in: 0..<TB2PTables.TWIST)

        var cubie: TB2PCubieCube
        repeat {
            cubie = TB2PCubieCube()
            cubie.flip = flip
            cubie.twist = twist
            cubie.corner = Int.random(in: 0..<TB2PTables.CORNER)
            cubie.edge = Int.random(in: 0..<TB2PTables.EDGE)
        } while cubie.edgeParity != cubie.cornerParity

        return String(describing: TB2PFaceCube(from: cubie))
    }

    /// Installs the bundled lookup tables for cube operations in the
    /// user's cache directory. This allows the library to load tables from
    /// disk instead of generating them.
    ///
    /// If the tables file does not exist at the expected destination, this
    /// method copies it from the app bundle.
    ///
    /// - Throws: An error if copying or moving the tables file fails.
    public static func installTables() throws {
        let fileManager = FileManager.default

        let destinationURL = TB2PTables.binFileURL
        guard !fileManager.fileExists(atPath: destinationURL.path) else { return }

        guard let bundleURL = Bundle.module.url(forResource: "TB2PTables", withExtension: "bin")
        else { return }

        let temporaryURL = destinationURL.appendingPathExtension("tmp")
        try fileManager.copyItem(at: bundleURL, to: temporaryURL)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    /// 本项目补丁：查询表资源是否随包打进了产物。
    ///
    /// 上游 `tables` 在加载失败时直接 `fatalError`，调用方无从捕获；这里加一个
    /// 纯查询入口，让调用方能在资源缺失时优雅降级而不是崩掉宿主 App。
    /// 只读、无副作用，不改变任何既有行为。
    public static var isTablesResourceBundled: Bool {
        Bundle.module.url(forResource: "TB2PTables", withExtension: "bin") != nil
    }

    /// Lazily initializes and provides access to the precomputed lookup tables
    /// required for cube operations.
    ///
    /// This property loads the tables from disk or generates them if necessary.
    public static let tables: TB2PTables = {
        do {
            return try TB2PTables.loadFromBinary()
        } catch {
            fatalError("TB2PTables init failed: \(error)")
        }
    }()

}
