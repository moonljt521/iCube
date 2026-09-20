import XCTest
@testable import CubeKit

final class LayerTurnTests: XCTestCase {

    func test_roundTripsEveryLayerMove() {
        for kind in MoveKind.all where !kind.isWholeCube {
            for amount in MoveAmount.allCases {
                let move = Move(kind, amount)
                let center = Self.sampleCenter(in: kind)
                let rotation = Rotation(axis: kind.axis, quarterTurns: move.quarterTurns)
                let recovered = Move.layerTurn(axis: kind.axis, rotation: rotation, affecting: center)
                XCTAssertEqual(recovered, move, "\(kind.letter)\(amount.suffix) 反推失败")
            }
        }
    }

    /// 手工核对的几个方向，防止整条链路同时反向
    func test_handCheckedDirections() {
        // 绕 +Y 转 3 个 90°（即 -90°）就是俯视顺时针，即 U
        XCTAssertEqual(Move.layerTurn(axis: .y, rotation: Rotation(axis: .y, quarterTurns: 3), affecting: V3(2, 2, 2)),
                       Move.u)
        XCTAssertEqual(Move.layerTurn(axis: .y, rotation: Rotation(axis: .y, quarterTurns: 1), affecting: V3(2, 2, 2)),
                       Move.uPrime)
        // 中层：(2,0,0) 在 y 轴的中层切片上，绕 +Y 转 1 步 = E
        XCTAssertEqual(Move.layerTurn(axis: .y, rotation: Rotation(axis: .y, quarterTurns: 1), affecting: V3(2, 0, 0)),
                       Move.e)
        // 右前上角所在 x 层：绕 +X 转 3 步 = R
        XCTAssertEqual(Move.layerTurn(axis: .x, rotation: Rotation(axis: .x, quarterTurns: 3), affecting: V3(2, 2, 2)),
                       Move.r)
        // 后下左角在 D 层：绕 +Z 转 1 步 = B
        XCTAssertEqual(Move.layerTurn(axis: .z, rotation: Rotation(axis: .z, quarterTurns: 1), affecting: V3(-2, -2, -2)),
                       Move.b)
    }

    /// 原点属于每一轴的中层，反推应落到中层记法而不是整体旋转
    func test_centerOnAxisPlaneResolvesToSlice() {
        XCTAssertEqual(Move.layerTurn(axis: .y, rotation: Rotation(axis: .y, quarterTurns: 3), affecting: .zero),
                       Move.ePrime)
        let recovered = Move.layerTurn(axis: .x, rotation: Rotation(axis: .x, quarterTurns: 1), affecting: .zero)
        XCTAssertEqual(recovered?.kind, .slice(.m))
    }

    func test_axisLookupRejectsNonAxisVectors() {
        XCTAssertEqual(CubeAxis.axis(of: V3(0, -1, 0)), .y)
        XCTAssertEqual(CubeAxis.axis(of: V3(1, 0, 0)), .x)
        XCTAssertNil(CubeAxis.axis(of: V3(1, 1, 0)))
        XCTAssertNil(CubeAxis.axis(of: .zero))
    }

    /// 取一个确实落在该转动层内的块中心
    private static func sampleCenter(in kind: MoveKind) -> V3 {
        switch kind {
        case .face(let face):
            return face.normal * 2
        case .slice(let slice):
            let perpendicular = CubeAxis.allCases.first { $0 != slice.referenceFace.axis }!
            return perpendicular.unit * 2
        case .rotation:
            return .zero
        }
    }
}
