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
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass 已经钉死，这个转换不会失败
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // 连接要等 session 配上输入之后才存在，所以每次布局都补一次。
            // 应用锁竖屏，所以固定 90°。
            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
