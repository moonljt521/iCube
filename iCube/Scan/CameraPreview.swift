import AVFoundation
import SwiftUI
import UIKit

/// 把 `AVCaptureVideoPreviewLayer` 塞进 SwiftUI。
///
/// `.resizeAspect` 是必须的（不是 `resizeAspectFill`）：`ScanGeometry` 的映射
/// 假设画面等比缩放并居中留黑边。换成 fill 会裁切，屏幕上的引导框和实际采样的
/// 区域就对不上了——而且这种偏差在真机上极难发现，只有识别结果悄悄偏一格。
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspect
        view.bind(to: session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.bind(to: session)
    }

    final class PreviewView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass 已经钉死，这个转换不会失败
            layer as! AVCaptureVideoPreviewLayer
        }

        private var runningObservation: NSKeyValueObservation?

        /// 接上会话，并在会话真正跑起来的那一刻补设画面方向。
        ///
        /// 光靠 `layoutSubviews` 设方向是不够的：`previewLayer.connection` 要等
        /// 会话配上输入之后才存在，而会话是在后台队列上异步配置的——首次布局时
        /// 它多半还是 nil，此后视图尺寸不再变化，就再没有机会补上了，预览会一直
        /// 横着显示（而引导框是竖的，两者完全对不上）。
        ///
        /// `isRunning` 是文档明确支持 KVO 的属性，它一变 true 连接必定已经就位。
        func bind(to session: AVCaptureSession) {
            guard previewLayer.session !== session else {
                applyRotation()
                return
            }
            previewLayer.session = session
            runningObservation = session.observe(\.isRunning, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyRotation() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyRotation()
        }

        /// 应用锁竖屏，所以画面固定转 90°。
        ///
        /// 转的是哪个方向不影响识别结果：引导框是居中的正方形，绕中心转 90°
        /// 不影响它；受影响的只有 3×3 各格的排列次序，而 `FaceletAssembler`
        /// 本来就要枚举四种朝向。详见 `ScanGeometry.guideRectInFrame`。
        private func applyRotation() {
            guard let connection = previewLayer.connection,
                  connection.isVideoRotationAngleSupported(90),
                  connection.videoRotationAngle != 90
            else { return }
            connection.videoRotationAngle = 90
        }
    }
}
