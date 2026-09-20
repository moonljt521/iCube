import XCTest
@testable import CubeKit

final class GeometryTests: XCTestCase {

    func test_54StickersAreUnique() {
        XCTAssertEqual(StickerGeometry.all.count, 54)
        XCTAssertEqual(Set(StickerGeometry.all).count, 54, "贴纸槽位存在重复，网格定义有误")
        XCTAssertEqual(StickerGeometry.indexByGeometry.count, 54)
    }

    func test_stickerCentersSitOnSurface() {
        for sticker in StickerGeometry.all {
            let alongNormal = sticker.center.dot(sticker.normal)
            XCTAssertEqual(alongNormal, 3, "贴纸中心必须落在立方体表面")
            let tangential = sticker.center - sticker.normal * 3
            for component in [tangential.x, tangential.y, tangential.z] {
                XCTAssertTrue([-2, 0, 2].contains(component), "切向坐标必须是块中心：\(sticker.center)")
            }
        }
    }

    func test_faceAxesFormRightHandedBasis() {
        for face in Face.allCases {
            XCTAssertEqual(face.normal.dot(face.up), 0)
            XCTAssertEqual(face.normal.dot(face.right), 0)
            XCTAssertEqual(face.up.dot(face.right), 0)
            // 正视该面时 right × up = 朝向观察者的法向
            XCTAssertEqual(face.right.cross(face.up), face.normal, "\(face.letter) 面的 right/up 手性不对")
            XCTAssertEqual(face.sign, face.normal.dot(face.axis.unit))
        }
    }

    func test_faceTurnMovesExpectedStickerCount() {
        // 该面 9 个贴纸里中心不动，加 4 个邻面各 3 个 = 20
        for face in Face.allCases {
            for amount in MoveAmount.allCases {
                let moved = TurnTable.permutation(for: Move(.face(face), amount)).movedIndices.count
                XCTAssertEqual(moved, 20, "\(face.letter)\(amount.suffix) 应移动 20 个贴纸")
            }
        }
    }

    func test_sliceTurnMovesExpectedStickerCount() {
        // 中层含 4 个中心块：4 个面各 3 个贴纸 = 12
        for slice in SliceKind.allCases {
            XCTAssertEqual(TurnTable.permutation(for: Move(.slice(slice))).movedIndices.count, 12)
            XCTAssertEqual(TurnTable.permutation(for: Move(.slice(slice), .half)).movedIndices.count, 12)
        }
    }

    func test_wholeCubeRotationMovesExpectedStickerCount() {
        // 绕任一轴旋转只有轴上两个中心不动
        for rotation in CubeRotation.allCases {
            XCTAssertEqual(TurnTable.permutation(for: Move(.rotation(rotation))).movedIndices.count, 52)
        }
    }

    func test_allPermutationsAreBijections() {
        for kind in GeometryTests.allKinds() {
            for amount in MoveAmount.allCases {
                let source = TurnTable.permutation(for: Move(kind, amount)).source
                XCTAssertEqual(Set(source).count, 54, "\(kind.letter) 置换非法")
            }
        }
    }

    func test_quarterTurnFourTimesIsIdentity() {
        for kind in GeometryTests.allKinds() {
            for amount in [MoveAmount.cw, .ccw] {
                let move = Move(kind, amount)
                var state = CubeState.solved
                for _ in 0..<4 { state.apply(move) }
                XCTAssertTrue(state.isSolved, "\(move.notation) 连做 4 次应回到还原态")
            }
        }
    }

    func test_halfTurnEqualsTwoQuarterTurns() {
        for kind in GeometryTests.allKinds() {
            let cw = TurnTable.permutation(for: Move(kind, .cw)).source
            let half = TurnTable.permutation(for: Move(kind, .half)).source
            XCTAssertEqual(cw.map { cw[$0] }, half, "\(kind.letter)2 与连续两次顺时针不等价")
        }
    }

    func test_inversePermutationUndoesTurn() {
        for kind in GeometryTests.allKinds() {
            let move = Move(kind, .cw)
            let forward = TurnTable.permutation(for: move).source
            let backward = TurnTable.permutation(for: move.inverse).source
            XCTAssertEqual(forward.map { backward[$0] }, Array(0..<54))
        }
    }

    func test_centersNeverMoveUnderFaceTurns() {
        // 6 个中心块随刚体固定，外层转动不会挪动任何一个（只有中层转动会）
        for face in Face.allCases {
            let source = TurnTable.permutation(for: Move(.face(face))).source
            for other in Face.allCases {
                let center = faceletIndex(other, row: 1, col: 1)
                XCTAssertEqual(source[center], center, "\(face.letter) 转动挪动了 \(other.letter) 中心")
            }
        }
    }

    func test_sliceTurnsMoveFourCenters() {
        for slice in SliceKind.allCases {
            let source = TurnTable.permutation(for: Move(.slice(slice))).source
            let movedCenters = Face.allCases.filter { other in
                source[faceletIndex(other, row: 1, col: 1)] != faceletIndex(other, row: 1, col: 1)
            }
            XCTAssertEqual(movedCenters.count, 4, "\(slice.letter) 应挪动 4 个中心块")
        }
    }

    /// 渲染层用的公开入口必须与几何表逐槽位一致
    func test_indexLookupMatchesGeometryTable() {
        for (expected, geometry) in StickerGeometry.all.enumerated() {
            let cubieCenter = geometry.center - geometry.normal
            XCTAssertEqual(StickerGeometry.index(cubieCenter: cubieCenter, facing: geometry.normal), expected,
                           "槽位 \(expected) 的反查结果不一致")
        }
        XCTAssertNil(StickerGeometry.index(cubieCenter: .zero, facing: .posZ), "核心块不应有贴纸")
        XCTAssertNil(StickerGeometry.index(cubieCenter: V3(2, 2, 2), facing: .negX), "朝内方向不应有贴纸")
        XCTAssertNil(StickerGeometry.index(cubieCenter: V3(0, 0, 2), facing: .posX), "中层朝右不是表面")
    }

    static func allKinds() -> [MoveKind] {
        MoveKind.all
    }
}
