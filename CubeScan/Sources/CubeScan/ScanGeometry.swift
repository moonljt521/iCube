import CoreGraphics
import Foundation

/// 取景框的几何：视频画面在屏幕上的位置、3×3 引导方框的位置、以及每一格的采样区域。
///
/// 纯几何、不碰 AVFoundation，可以直接单测——这类"坐标系算错一格"的 bug
/// 在真机上极难发现（画面看起来是对的，只有识别结果悄悄偏了一格）。
///
/// 坐标约定：
/// - **视图坐标**：左上原点，y 向下，单位是视图的 point
/// - **归一化视频坐标**：左上原点，y 向下，0...1，直接喂给 `StickerSampler`
///
/// 预览层用 `.resizeAspect`（不是 `resizeAspectFill`）：等比缩放并留黑边，
/// 视频矩形与视图的映射是纯线性缩放。用 fill 会裁切，屏幕上的引导框和实际
/// 采样的区域就对不上了。
public struct ScanGeometry: Hashable, Sendable {

    /// 预览视图的尺寸
    public let viewSize: CGSize
    /// 视频画面在视图里的矩形（.resizeAspect 下居中留边）
    public let videoRect: CGRect
    /// 引导方框：视频矩形里居中的正方形
    public let guideRect: CGRect

    public init(videoSize: CGSize, viewSize: CGSize, guideRatio: Double = 0.82) {
        self.viewSize = viewSize
        let video = Self.fit(videoSize: videoSize, into: viewSize)
        self.videoRect = video
        let side = min(video.width, video.height) * CGFloat(guideRatio)
        self.guideRect = CGRect(
            x: video.midX - side / 2,
            y: video.midY - side / 2,
            width: side,
            height: side
        )
    }

    /// `.resizeAspect` 的映射：等比缩放到刚好装进视图，居中
    public static func fit(videoSize: CGSize, into viewSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let scale = min(viewSize.width / videoSize.width, viewSize.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(
            x: (viewSize.width - size.width) / 2,
            y: (viewSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 第 index 格（row-major，0 是左上）在视图坐标里的**采样区域**。
    /// 已经按 `inset` 向内收缩——贴着格子边缘采会吃到贴纸之间的黑色塑料。
    ///
    /// 这里两个方向分开算步长，和 `StickerSampler.cellRect` 保持一致。`guideRect`
    /// 本身是正方形，分开算与合并算结果相同；但合并算是个陷阱——换个非正方形的
    /// 引导框就会静默压扁，而这类"坐标算错一格"的 bug 在真机上极难发现。
    public func cellRect(_ index: Int, inset: Double = 0.18) -> CGRect {
        let row = index / 3
        let col = index % 3
        let cellWidth = guideRect.width / 3
        let cellHeight = guideRect.height / 3
        let cell = CGRect(
            x: guideRect.minX + CGFloat(col) * cellWidth,
            y: guideRect.minY + CGFloat(row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        return cell.insetBy(dx: CGFloat(inset) * cellWidth, dy: CGFloat(inset) * cellHeight)
    }

    /// 视图坐标 → 归一化视频坐标
    public func normalized(_ point: CGPoint) -> CGPoint {
        guard videoRect.width > 0, videoRect.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - videoRect.minX) / videoRect.width,
            y: (point.y - videoRect.minY) / videoRect.height
        )
    }

    /// 视图坐标的矩形 → 归一化视频坐标的矩形
    public func normalized(_ rect: CGRect) -> CGRect {
        let origin = normalized(rect.origin)
        guard videoRect.width > 0, videoRect.height > 0 else { return .zero }
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width / videoRect.width,
            height: rect.height / videoRect.height
        )
    }

    /// 第 index 格的采样区域，归一化视频坐标，可直接交给 `StickerSampler`
    public func normalizedCellRect(_ index: Int, inset: Double = 0.18) -> CGRect {
        normalized(cellRect(index, inset: inset))
    }

    /// 引导框落在**相机原始帧**里的归一化矩形，直接喂给 `StickerSampler.sampleGrid`。
    ///
    /// ## 为什么需要一个单独的入口
    ///
    /// 相机交给我们的帧和预览层显示出来的画面，朝向通常不一样：后置摄像头的原始帧
    /// 是横的（1280×720），而应用锁竖屏、预览层把它转成了竖的。`ScanGeometry`
    /// 其余部分描述的是**屏幕上看到的样子**，所以采样前要做这一步换算。
    ///
    /// ## 为什么不需要知道转了多少度
    ///
    /// 引导框是**居中的正方形**，而"绕中心旋转"和"按比例居中留边"这两件事都把
    /// 中心映到中心、把正方形映成同尺寸的正方形。所以引导框在帧里永远是居中的
    /// 正方形，只要把边长算对就行——转的是哪个方向，甚至转没转，都不影响它。
    ///
    /// 受方向影响的只有 3×3 各格的**排列次序**：帧里的 row-major 次序可能是屏幕上
    /// 看到的那个网格整体转了 90°/180°。这也没关系——`FaceletAssembler` 本来就要
    /// 枚举四种朝向，转过的格子它自己会摆正。**刻意不去追这个方向**，因为算错了
    /// 方向会得到一个镜像，而镜像不是旋转、拼不回去；干脆不追，就没有算错的机会。
    ///
    /// 帧尺寸按"摆成竖的"来理解：应用锁竖屏，所以预览里显示出来的画面是竖的。
    public func guideRectInFrame(frameSize: CGSize) -> CGRect {
        let fallback = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        guard frameSize.width > 0, frameSize.height > 0,
              viewSize.width > 0, viewSize.height > 0,
              guideRect.width > 0
        else { return fallback }

        let displayed = frameSize.width > frameSize.height
            ? CGSize(width: frameSize.height, height: frameSize.width)
            : frameSize
        let scale = min(viewSize.width / displayed.width, viewSize.height / displayed.height)
        guard scale > 0 else { return fallback }

        // 旋转不改变长度，所以引导框在帧里的边长（像素）与在显示画面里一致
        let side = guideRect.width / scale
        let width = min(side / frameSize.width, 1)
        let height = min(side / frameSize.height, 1)
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
}
