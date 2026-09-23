import Foundation

/// 整体旋转的全部 24 种组合（x/y/z 各 0~3 个 90° 的笛卡尔积里 64 条，含重复）。
/// 重复不要紧——调用方都是"存在性判断"或"取极值"，重复不影响结果。
enum WholeCubeRotations {
    static let all: [Algorithm] = {
        var result: [Algorithm] = []
        for x in 0..<4 {
            for y in 0..<4 {
                for z in 0..<4 {
                    var moves: [Move] = []
                    for _ in 0..<x { moves.append(Move(.rotation(.x), .cw)) }
                    for _ in 0..<y { moves.append(Move(.rotation(.y), .cw)) }
                    for _ in 0..<z { moves.append(Move(.rotation(.z), .cw)) }
                    result.append(Algorithm(moves))
                }
            }
        }
        return result
    }()
}

public extension CubeState {

    /// 落在自己归属位置上的贴纸数（还原态 = 6N²）
    var homeStickerCount: Int {
        let solved = CubeState.solvedColors(size: size)
        var count = 0
        for (index, color) in stickers.enumerated() where color == solved[index] { count += 1 }
        return count
    }

    /// 与 `other` 是否只差一个整体旋转
    func isRotationEquivalent(to other: CubeState) -> Bool {
        guard size == other.size else { return false }
        return WholeCubeRotations.all.contains { applying($0) == other }
    }

    /// 在"只差一个整体旋转"的一族写法里挑一个确定的代表。
    ///
    /// ## 为什么需要
    ///
    /// 奇数阶有中心块锚定（`legality` 要求中心各就各位），同一颗魔方只有一种写法；
    /// 偶数阶没有固定中心块，**24 种整体旋转全都是合法状态**。拍照识别只能给出
    /// "其中一个"，不规范化的话同一颗魔方每次识别出来的朝向都会乱跳，
    /// 录入页也就没法跟手上的魔方对照。
    ///
    /// ## 挑法
    ///
    /// 取**贴纸落在自己归属位置最多的那个**——也就是"最像还原态"的那个写法，
    /// 与用户把魔方白顶绿前拿在手里的习惯最接近；同分时取贴纸序列字典序最小的，
    /// 保证确定性。三阶原样返回，不做多余的事。
    var rotationallyCanonical: CubeState {
        guard size != 3 else { return self }
        var best = self
        var bestScore = homeStickerCount
        for rotation in WholeCubeRotations.all {
            let candidate = applying(rotation)
            let score = candidate.homeStickerCount
            if score > bestScore || (score == bestScore && candidate.isLexicographicallyPreceding(best)) {
                best = candidate
                bestScore = score
            }
        }
        return best
    }

    /// 贴纸序列的字典序比较，仅用于打破并列
    func isLexicographicallyPreceding(_ other: CubeState) -> Bool {
        for (lhs, rhs) in zip(stickers, other.stickers) where lhs != rhs {
            return lhs.rawValue < rhs.rawValue
        }
        return false
    }
}

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
