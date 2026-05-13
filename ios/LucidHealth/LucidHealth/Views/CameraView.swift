import SwiftUI
import UIKit

/// UIImagePickerController wrapper — presents ReviewView on capture.
struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onSaved: (FoodEntry) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView

        init(parent: CameraView) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.dismiss()
                return
            }
            let reviewVC = UIHostingController(rootView:
                ReviewView(image: image, onSaved: { entry in
                    self.parent.onSaved(entry)
                    self.parent.dismiss()
                })
            )
            reviewVC.modalPresentationStyle = .fullScreen
            picker.present(reviewVC, animated: true)
        }
    }
}
