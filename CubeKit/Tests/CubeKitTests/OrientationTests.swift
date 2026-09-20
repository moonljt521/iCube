import XCTest
@testable import CubeKit

final class OrientationTests: XCTestCase {

    func test_identityMapsEachViewFaceToItself() {
        for face in Face.allCases {
            XCTAssertEqual(CubeOrientation.identity.bodyFace(forView: face), face)
            XCTAssertEqual(CubeOrientation.identity.viewFace(forBody: face), face)
        }
    }

    /// x 跟随 R：F 面翻到顶上
    func test_xRotationBringsFrontToTop() {
        let afterX = CubeOrientation.identity.rotating(by: .x)
        XCTAssertEqual(afterX.bodyFace(forView: .u), .f)
        XCTAssertEqual(afterX.bodyFace(forView: .f), .d)
        XCTAssertEqual(afterX.bodyFace(forView: .d), .b)
        XCTAssertEqual(afterX.bodyFace(forView: .b), .u)
        XCTAssertEqual(afterX.bodyFace(forView: .r), .r, "x 绕 R 轴，右面自转不变")
        XCTAssertEqual(afterX.bodyFace(forView: .l), .l)
    }

    /// y 跟随 U：R 面转到前面
    func test_yRotationBringsRightToFront() {
        let afterY = CubeOrientation.identity.rotating(by: .y)
        XCTAssertEqual(afterY.bodyFace(forView: .f), .r)
        XCTAssertEqual(afterY.bodyFace(forView: .r), .b)
        XCTAssertEqual(afterY.bodyFace(forView: .b), .l)
        XCTAssertEqual(afterY.bodyFace(forView: .l), .f)
        XCTAssertEqual(afterY.bodyFace(forView: .u), .u)
    }

    /// z 跟随 F：U→R→D→L→U，即本体 U 面此刻出现在视图右侧
    func test_zRotationCycle() {
        let afterZ = CubeOrientation.identity.rotating(by: .z)
        XCTAssertEqual(afterZ.bodyFace(forView: .r), .u)
        XCTAssertEqual(afterZ.bodyFace(forView: .d), .r)
        XCTAssertEqual(afterZ.bodyFace(forView: .l), .d)
        XCTAssertEqual(afterZ.bodyFace(forView: .u), .l)
        XCTAssertEqual(afterZ.bodyFace(forView: .f), .f)
        XCTAssertEqual(afterZ.bodyFace(forView: .b), .b)
    }

    func test_rotationsAreInvertible() {
        for move in [Move.x, Move.y, Move.z] {
            let roundTrip = CubeOrientation.identity.rotating(by: move).rotating(by: move.inverse)
            XCTAssertEqual(roundTrip, .identity)
            let fourTimes = [move, move, move, move].reduce(CubeOrientation.identity) { $0.rotating(by: $1) }
            XCTAssertEqual(fourTimes, .identity, "\(move.notation) 四次应回到原朝向")
        }
    }

    func test_exactly24OrientationsReachable() {
        var seen: Set<CubeOrientation> = [.identity]
        var frontier: [CubeOrientation] = [.identity]
        let generators = [Move.x, Move.y, Move.z]
        while let current = frontier.popLast() {
            for move in generators {
                let next = current.rotating(by: move)
                if !seen.contains(next) {
                    seen.insert(next)
                    frontier.append(next)
                }
            }
        }
        XCTAssertEqual(seen.count, 24, "三阶魔方整体朝向恰好 24 种")
    }

    func test_viewBodyMappingRoundTripsForAll24() {
        for orientation in allOrientations() {
            for face in Face.allCases {
                XCTAssertEqual(orientation.viewFace(forBody: orientation.bodyFace(forView: face)), face)
            }
            // 三个视图基向必须落在互相垂直的本体轴上
            XCTAssertEqual(orientation.right.cross(orientation.up), orientation.front)
        }
    }

    func test_bodyMoveWithIdentityOrientationIsUnchanged() {
        for move in [Move.u, Move.rPrime, Move.f2, Move.m, Move(.slice(.s), .half)] {
            XCTAssertEqual(CubeOrientation.identity.bodyMove(for: move), move)
        }
    }

    /// x 之后：视图 U 层就是本体 F 层，方向语义一致
    func test_bodyMoveAfterX() {
        let afterX = CubeOrientation.identity.rotating(by: .x)
        XCTAssertEqual(afterX.bodyMove(for: .u), Move(.face(.f)))
        XCTAssertEqual(afterX.bodyMove(for: .d), Move(.face(.b)))
        XCTAssertEqual(afterX.bodyMove(for: .r), Move(.face(.r)))
        XCTAssertEqual(afterX.bodyMove(for: .m), Move(.slice(.m)), "x 绕 R 轴，视图 M 仍是本体 M")
    }

    /// y 之后：视图 M 落到本体 S，视图 S 落到本体 M'——这类跨轴换算是静默 bug 的高发区
    func test_bodyMoveAfterY() {
        let afterY = CubeOrientation.identity.rotating(by: .y)
        XCTAssertEqual(afterY.bodyMove(for: .m), Move(.slice(.s)))
        XCTAssertEqual(afterY.bodyMove(for: .s), Move(.slice(.m), .ccw))
        XCTAssertEqual(afterY.bodyMove(for: .u), Move(.face(.u)))
        XCTAssertEqual(afterY.bodyMove(for: .f), Move(.face(.r)))
    }

    /// 组合朝向：x 把 F 送上顶，y 只绕竖轴自转，所以视图 U 仍是本体 F，
    /// 完整映射为 (view x,y,z) → (body z,x,y)
    func test_bodyMoveAfterComposedOrientation() {
        let combined = CubeOrientation.identity.rotating(by: .x).rotating(by: .y)
        XCTAssertEqual(combined.bodyFace(forView: .u), .f)
        XCTAssertEqual(combined.bodyFace(forView: .d), .b)
        XCTAssertEqual(combined.bodyFace(forView: .r), .u)
        XCTAssertEqual(combined.bodyFace(forView: .l), .d)
        XCTAssertEqual(combined.bodyFace(forView: .f), .r)
        XCTAssertEqual(combined.bodyFace(forView: .b), .l)
        XCTAssertEqual(combined.bodyMove(for: .u), Move(.face(.f)))
    }

    func test_rotatingByNonRotationMoveIsNoOp() {
        XCTAssertEqual(CubeOrientation.identity.rotating(by: .u), .identity)
    }

    private func allOrientations() -> [CubeOrientation] {
        var seen: Set<CubeOrientation> = [.identity]
        var frontier: [CubeOrientation] = [.identity]
        while let current = frontier.popLast() {
            for move in [Move.x, Move.y, Move.z] {
                let next = current.rotating(by: move)
                if seen.insert(next).inserted { frontier.append(next) }
            }
        }
        return Array(seen)
    }
}
