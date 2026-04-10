import SwiftUI
import PhotosUI
import UIKit

/// Presents camera or photo library; returns selected image as JPEG data via onPicked.
struct PlateImagePickerView: UIViewControllerRepresentable {
    enum Source: String, Identifiable {
        case camera
        case photoLibrary

        var id: String { rawValue }
    }
    let source: Source
    let onPicked: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .camera:
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
            picker.allowsEditing = false
            return picker
        case .photoLibrary:
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .images
            configuration.selectionLimit = 1

            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = context.coordinator
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
        let parent: PlateImagePickerView

        init(_ parent: PlateImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                parent.onPicked(data)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onCancel()
                return
            }

            let provider = result.itemProvider
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        if let image = object as? UIImage,
                           let data = image.jpegData(compressionQuality: 0.85) {
                            self.parent.onPicked(data)
                        } else {
                            self.parent.onCancel()
                        }
                    }
                }
                return
            }

            parent.onCancel()
        }
    }
}
