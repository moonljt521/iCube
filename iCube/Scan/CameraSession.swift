import AVFoundation
import Foundation

/// 最薄的一层相机包装：后置摄像头 → BGRA 帧。
///
/// 只做"把帧交出来"这一件事——不解析、不留状态、不管权限，那些都在 `ScanModel`。
/// 相机这一层因此几乎没有可测的逻辑，也就不需要测试替身；真正要测的几何和颜色
/// 都在 `CubeScan` 里，那边是纯函数。
final class CameraSession: NSObject {

    /// 会话配置失败的原因。
    ///
    /// 这里只给原因，不给文案——翻译成中文留在应用层，和 `ScanError`、
    /// `CubeSolveError` 一个路子。
    enum Failure: Error {
        /// 拿不到后置摄像头，或者构造输入失败（相机被别的 App 占用时会走到这里）
        case cannotCreateInput
        /// 会话不接受这个输入
        case cannotAddInput
        /// 会话不接受这个输出
        case cannotAddOutput
    }

    /// 每帧回调。**在专用串行队列上调用**，回调里不要碰 UI。
    /// 拿到的 `CVPixelBuffer` 只在回调期间有效，要留数据得自己拷出来。
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// 配置失败时回调。**在主线程上调用。**
    ///
    /// 没有这个出口的话，失败就是静默的：会话起不来 → 永远没有帧 →
    /// 界面上是黑屏加一个点不动的快门，用户完全不知道发生了什么。
    var onFailure: ((Failure) -> Void)?

    let session = AVCaptureSession()

    /// 相机相关操作都在这条队列上，避免和 `startRunning()` 的阻塞打架
    private let queue = DispatchQueue(label: "com.moonding.icube.scan.camera")
    private var isConfigured = false
    private var isFailed = false

    /// 相机可用（模拟器上没有，用于界面上给出可读的说明）
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func start() {
        queue.async { [self] in
            if !isConfigured && !isFailed {
                if let failure = configure() {
                    isFailed = true
                    DispatchQueue.main.async { onFailure?(failure) }
                    return
                }
            }
            guard isConfigured, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    // MARK: - 配置

    /// 返回 nil 表示配置成功
    private func configure() -> Failure? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            return .cannotCreateInput
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 不支持就保持默认 preset——帧尺寸是运行时从像素缓冲读的，
        // `ScanGeometry.guideRectInFrame` 会自适应，不会因此算错格子
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        guard session.canAddInput(input) else { return .cannotAddInput }
        session.addInput(input)

        // 魔方离镜头很近，把对焦范围收到近端：不然连续对焦会来回拉风箱，
        // 采样到的颜色跟着忽明忽暗。
        if let _ = try? device.lockForConfiguration() {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // 处理跟不上就丢帧，别排队——识别要的是"当前这一帧"，不是三秒前的
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else { return .cannotAddOutput }
        session.addOutput(output)

        // 刻意**不**设置输出连接的方向。理由见 `ScanGeometry.guideRectInFrame`：
        // 引导框是居中的正方形，绕中心转 90° 不影响它，格子次序整体转一下
        // `FaceletAssembler` 会摆正。少一处能算错的地方。
        isConfigured = true
        return nil
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer)
    }
}
