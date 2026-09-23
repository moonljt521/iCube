import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 从相册里选一个视频。
///
/// 用 `PHPickerViewController` 而不是 `UIImagePickerController`：后者要完整的
/// 相册读写权限，前者是系统代持的一次性授权，用户不用为"选一个视频"就交出整个相册。
struct VideoPicker: UIViewControllerRepresentable {

    /// 选完回调。参数是拷到临时目录后的文件（用户取消或失败时为 nil）
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            else {
                onPick(nil)
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                guard let self, let url else {
                    DispatchQueue.main.async { self?.onPick(nil) }
                    return
                }
                // 必须拷走：provider 给的这个 URL 在回调返回之后就失效了
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                let copied = (try? FileManager.default.copyItem(at: url, to: destination)) != nil
                DispatchQueue.main.async { self.onPick(copied ? destination : nil) }
            }
        }
    }
}
