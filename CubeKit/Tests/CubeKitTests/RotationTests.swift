import XCTest
@testable import CubeKit

final class RotationTests: XCTestCase {

    func test_matchesVectorRotation() {
        for axis in CubeAxis.allCases {
            for turns in 0..<4 {
                let rotation = Rotation(axis: axis, quarterTurns: turns)
                for unit in [V3.posX, .negX, .posY, .negY, .posZ, .negZ] {
                    XCTAssertEqual(rotation.applying(to: unit), unit.rotated(axis: axis, quarterTurns: turns))
                }
            }
        }
    }

    func test_columnsStayOrthonormal() {
        for rotation in reachableRotations() {
            XCTAssertEqual(rotation.xAxis.cross(rotation.yAxis), rotation.zAxis)
            XCTAssertEqual(rotation.applying(to: .posX).dot(rotation.applying(to: .posY)), 0)
        }
    }

    func test_groupHasExactly24Elements() {
        XCTAssertEqual(Set(reachableRotations()).count, 24, "三阶魔方姿态群应为 24 个元素")
    }

    func test_inverseIsTwoSided() {
        for rotation in reachableRotations() {
            XCTAssertEqual(rotation.then(rotation.inverse), .identity)
            XCTAssertEqual(rotation.inverse.then(rotation), .identity)
        }
    }

    func test_compositionAppliesInOrder() {
        let a = Rotation(axis: .x, quarterTurns: 1)
        let b = Rotation(axis: .y, quarterTurns: 3)
        let composed = a.then(b)
        for vector in [V3(2, 2, 2), V3(-2, 0, 2), V3(0, -2, 2)] {
            XCTAssertEqual(composed.applying(to: vector), b.applying(to: a.applying(to: vector)))
        }
        // 顺序不可交换
        XCTAssertNotEqual(a.then(b), b.then(a))
    }

    /// 渲染层用 Rotation 搬块体，状态层用置换表搬贴纸——两者必须逐槽位一致，
    /// 否则动画放完画面会和 isSolved 判定打架。同时校验"不在该层的贴纸一步都不许动"。
    func test_rotationAgreesWithFaceletPermutation() {
        for kind in [MoveKind.face(.u), .face(.d), .face(.f), .face(.b), .face(.r), .face(.l),
                     .slice(.m), .slice(.e), .slice(.s), .rotation(.x), .rotation(.y), .rotation(.z)] {
            for amount in MoveAmount.allCases {
                let move = Move(kind, amount)
                let rotation = Rotation(axis: kind.referenceFace.axis, quarterTurns: move.quarterTurns)
                let source = TurnTable.permutation(for: move).source
                for index in 0..<54 {
                    let from = source[index]
                    let geometry = StickerGeometry.all[from]
                    // 层归属按块中心判定：贴纸中心比块中心沿外法向多 1
                    let blockCenter = geometry.center - geometry.normal
                    guard move.affectsLayer(of: blockCenter) else {
                        XCTAssertEqual(from, index, "\(move.notation) 挪动了不该动的槽位 \(index)")
                        continue
                    }
                    XCTAssertEqual(rotation.applying(to: geometry.center), StickerGeometry.all[index].center,
                                   "\(move.notation) 槽位 \(index) 上矩阵与置换表不一致")
                    XCTAssertEqual(rotation.applying(to: geometry.normal), StickerGeometry.all[index].normal,
                                   "\(move.notation) 槽位 \(index) 法向不一致")
                }
            }
        }
    }

    private func reachableRotations() -> [Rotation] {
        var seen: Set<Rotation> = [.identity]
        var frontier: [Rotation] = [.identity]
        while let current = frontier.popLast() {
            for axis in CubeAxis.allCases {
                for turns in 1...3 {
                    let next = current.then(Rotation(axis: axis, quarterTurns: turns))
                    if seen.insert(next).inserted { frontier.append(next) }
                }
            }
        }
        return Array(seen)
    }
}
