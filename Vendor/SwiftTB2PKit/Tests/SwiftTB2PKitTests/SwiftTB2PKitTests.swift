import Foundation
import Testing

@testable import SwiftTB2PKit

struct SwiftTB2PKitTests {
    @Test func testSolve() {
        _ = TB2P.tables
        let facelets = "DFLRUBRDFRLDURRLRRUFDFFLBDFULUUDULBURBBBLRBFLFLBDBDFUD"
        let solver = try! TB2PSolver(facelets: facelets)
        let solution = try! solver.search()
        #expect(solution == "U2 B' U F L' U2 L' B' U L U R2 U' F2 B2 U' B2 R2 U' R2 F2 U L2 U")
    }

    @Test func testSolveSuperflip() {
        _ = TB2P.tables
        let facelets = "UBULURUFURURFRBRDRFUFLFRFDFDFDLDRDBDLULBLFLDLBUBRBLBDB"
        let solver = try! TB2PSolver(facelets: facelets)
        let solution = try! solver.search()
        // non-optimal solution
        #expect(solution == "R L F U D' R2 F2 R F B D B2 U R2 U L2 B2 D F2 B2 L2 F2 U2")
    }

    @Test func testRandom() {
        let facelets = TB2P.randomCube()
        let faceCube = try! TB2PFaceCube(cubeString: facelets)
        try! faceCube.toCubieCube().verify()
    }

    @Test func testFaceCubeInit() {
        let faceCube = try! TB2PFaceCube()
        let expectedString = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
        #expect("\(faceCube)" == expectedString)

        let customString = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
        let faceCube2 = try! TB2PFaceCube(cubeString: customString)
        #expect("\(faceCube2)" == customString)

        let twistedString = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB".reversed()
        let twistedCube = try! TB2PFaceCube(cubeString: String(twistedString))
        #expect("\(twistedCube)" == String(twistedString))
    }

    @Test func testFaceCubeInit_invalidLength() {
        let tooShort = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBB"  // 53
        do {
            _ = try TB2PFaceCube(cubeString: tooShort)
            Issue.record("Expected error for invalid length")
        } catch TB2PError.faceCubeInvalidFacelets(let str) {
            #expect(str == tooShort)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testFaceCubeInit_invalidFacelet() {
        let invalid = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBXBB"  // X
        do {
            _ = try TB2PFaceCube(cubeString: invalid)
            Issue.record("Expected error for invalid facelet")
        } catch TB2PError.faceCubeInvalidFacelet(let facelet, let idx) {
            #expect(facelet == "X")
            #expect(idx == 51)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testFaceCubeToCubieCube_identity() {
        let faceCube = try! TB2PFaceCube()
        let cubieCube = faceCube.toCubieCube()
        #expect(cubieCube.twist == 0)
        #expect(cubieCube.flip == 0)
        #expect(cubieCube.corner == 0)
        #expect(cubieCube.edge == 0)
    }

    @Test func testFaceCubeToCubieCube_roundtrip() {
        let facelets = TB2P.randomCube()
        let faceCube = try! TB2PFaceCube(cubeString: facelets)
        let cubieCube = faceCube.toCubieCube()
        let faceCube2 = TB2PFaceCube(from: cubieCube)
        #expect("\(faceCube)" == "\(faceCube2)")
    }

    @Test func testCubieCubeInit() {
        let cube = TB2PCubieCube()
        #expect(cube.cp == [.URF, .UFL, .ULB, .UBR, .DFR, .DLF, .DBL, .DRB])
        #expect(cube.co == Array(repeating: 0, count: 8))
        #expect(cube.ep == [.UR, .UF, .UL, .UB, .DR, .DF, .DL, .DB, .FR, .FL, .BL, .BR])
        #expect(cube.eo == Array(repeating: 0, count: 12))

        let cp: [TB2PCorner] = [.UBR, .URF, .UFL, .ULB, .DFR, .DLF, .DBL, .DRB]
        let co: [Int] = [1, 2, 0, 1, 2, 0, 1, 2]
        let ep: [TB2PEdge] = [.UB, .UR, .UF, .UL, .DR, .DF, .DL, .DB, .FR, .FL, .BL, .BR]
        let eo: [Int] = [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]
        let customCube = TB2PCubieCube(cp: cp, co: co, ep: ep, eo: eo)
        #expect(customCube.cp == cp)
        #expect(customCube.co == co)
        #expect(customCube.ep == ep)
        #expect(customCube.eo == eo)
    }

    @Test func testCubieCubeCornerMultiply() {
        let a = TB2PCubieCube()
        let b = TB2PCubieCube()
        // swap corners in b
        b.cp.swapAt(0, 1)
        b.co[0] = 1
        b.co[1] = 2
        a.cornerMultiply(b)
        #expect(a.cp == b.cp)
        #expect(a.co == b.co)
    }

    @Test func testCubieCubeEdgeMultiply() {
        let a = TB2PCubieCube()
        let b = TB2PCubieCube()
        // swap edges in b
        b.ep.swapAt(0, 1)
        b.eo[0] = 1
        b.eo[1] = 0
        a.edgeMultiply(b)
        #expect(a.ep == b.ep)
        #expect(a.eo == b.eo)
    }

    @Test func testCubieCubeMultiply() {
        let a = TB2PCubieCube()
        let b = TB2PCubieCube()
        b.cp = [.UBR, .UFL, .URF, .ULB, .DFR, .DLF, .DBL, .DRB]
        b.co = [1, 2, 0, 1, 2, 0, 1, 2]
        b.ep = [.UB, .UR, .UF, .UL, .DR, .DF, .DL, .DB, .FR, .FL, .BL, .BR]
        b.eo = [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]
        a.cp = [.UFL, .URF, .ULB, .UBR, .DFR, .DLF, .DBL, .DRB]
        a.co = [2, 1, 0, 2, 1, 0, 2, 1]
        a.ep = [.UR, .UF, .UL, .UB, .DR, .DF, .DL, .DB, .FR, .FL, .BL, .BR]
        a.eo = [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
        let bCopy = b
        let expectedCP: [TB2PCorner] = [.UBR, .URF, .UFL, .ULB, .DFR, .DLF, .DBL, .DRB]
        let expectedCO: [Int] = [0, 0, 2, 1, 0, 0, 0, 0]
        let expectedEP: [TB2PEdge] = [.UB, .UR, .UF, .UL, .DR, .DF, .DL, .DB, .FR, .FL, .BL, .BR]
        let expectedEO: [Int] = [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1]
        a.multiply(b)
        #expect(a.cp == expectedCP)
        #expect(a.co == expectedCO)
        #expect(a.ep == expectedEP)
        #expect(a.eo == expectedEO)
        #expect(a.cp.count == 8)
        #expect(a.co.count == 8)
        #expect(a.ep.count == 12)
        #expect(a.eo.count == 12)
        #expect(a.cp != bCopy.cp || a.co != bCopy.co || a.ep != bCopy.ep || a.eo != bCopy.eo)
    }

    @Test func testResourceLoading() throws {
        let url = Bundle.module.url(forResource: "TB2PTables", withExtension: "bin")
        #expect(url != nil)
        if let url = url {
            let data = try Data(contentsOf: url)
            #expect(!data.isEmpty)
        }
    }

    @Test func testTablesLoading() throws {
        let url = Bundle.module.url(forResource: "TB2PTables", withExtension: "bin")
        let loaded = try! TB2PTables.loadBinary(from: url!)
        let tables = TB2PTables.make()
        #expect(tables == loaded)
    }

    @Test func testTablesSavingJSON() throws {
        let tables = TB2PTables.make()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try TB2PTables.save(asJSON: tables, to: tempFile)
        let loaded = try TB2PTables.loadJSON(from: tempFile)
        #expect(tables == loaded)
    }

    @Test func testTablesSavingBinary() throws {
        let tables = TB2PTables.make()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("bin")
        try TB2PTables.save(asBinary: tables, to: tempFile)
        let loaded = try TB2PTables.loadBinary(from: tempFile)
        #expect(tables == loaded)
    }
}
