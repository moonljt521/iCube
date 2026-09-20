import Foundation

/// 魔方整体在空间中的朝向：记录"当前指向视图右/上/前三个方向的本体方向"。
/// 用户拖背景旋转视角只改这个值，不改 `CubeState`；把视图记法（教程/打乱里的 U、R）
/// 翻译成本体记法靠它。
public struct CubeOrientation: Hashable, Sendable {
    public let right: V3
    public let up: V3
    public let front: V3

    public init(right: V3, up: V3, front: V3) {
        self.right = right
        self.up = up
        self.front = front
    }

    public static let identity = CubeOrientation(right: .posX, up: .posY, front: .posZ)

    /// 视图方向 → 本体方向
    public func bodyDirection(forView direction: V3) -> V3 {
        right * direction.x + up * direction.y + front * direction.z
    }

    /// 本体方向 → 视图方向
    public func viewDirection(forBody direction: V3) -> V3 {
        var result = V3.zero
        for (axis, bodyDir) in [(CubeAxis.x, right), (.y, up), (.z, front)] {
            if bodyDir == direction { result = result + axis.unit }
            else if bodyDir == -direction { result = result - axis.unit }
        }
        return result
    }

    public func bodyFace(forView face: Face) -> Face {
        Face.facing(bodyDirection(forView: face.normal))!
    }

    public func viewFace(forBody face: Face) -> Face {
        Face.facing(viewDirection(forBody: face.normal))!
    }

    /// 绕视图坐标做整体旋转；只接受 `.rotation`，其余转动应走 `CubeState.apply`
    public func rotating(by move: Move) -> CubeOrientation {
        guard case .rotation = move.kind else { return self }
        let axis = move.kind.referenceFace.axis
        let inverseTurns = (4 - move.quarterTurns) % 4
        func inverseRotate(_ view: V3) -> V3 { view.rotated(axis: axis, quarterTurns: inverseTurns) }
        return CubeOrientation(
            right: bodyDirection(forView: inverseRotate(.posX)),
            up: bodyDirection(forView: inverseRotate(.posY)),
            front: bodyDirection(forView: inverseRotate(.posZ))
        )
    }

    /// 视图记法 → 本体记法。外层转动方向不变：本体面此刻正对着该视图方向，
    /// "从外侧看顺时针"在两个坐标系里指同一件事。
    /// 中层要额外处理：换算后的本体面可能落在该轴的另一侧（例如视图 M 变成本体 S），
    /// 此时顺时针语义相对 canonical 基准面反向。整体旋转请走 `rotating(by:)`。
    public func bodyMove(for viewMove: Move) -> Move {
        switch viewMove.kind {
        case .face(let viewFace):
            return Move(.face(bodyFace(forView: viewFace)), viewMove.amount, depth: viewMove.depth)

        case .slice(let slice):
            let bodyReference = bodyFace(forView: slice.referenceFace)
            let canonical = SliceKind(axisOf: bodyReference.axis)
            let sameDirection = bodyReference.sign == canonical.referenceFace.sign
            return Move(.slice(canonical), sameDirection ? viewMove.amount : viewMove.amount.inverse)

        case .rotation:
            return viewMove
        }
    }
}
