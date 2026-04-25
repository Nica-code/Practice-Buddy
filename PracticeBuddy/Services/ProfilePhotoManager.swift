import Foundation
import Combine
import UIKit
import FirebaseStorage

@MainActor
final class ProfilePhotoManager: ObservableObject {
    @Published private(set) var isUploading: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private let storage = Storage.storage()

    func uploadProfilePhoto(uid: String, imageData: Data) async -> String? {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else {
            lastErrorMessage = "Missing account ID."
            return nil
        }

        guard let source = UIImage(data: imageData) else {
            lastErrorMessage = "Could not read selected image."
            return nil
        }

        guard let processedData = Self.prepareUploadImageData(from: source) else {
            lastErrorMessage = "Could not process selected image."
            return nil
        }

        isUploading = true
        lastErrorMessage = nil
        defer { isUploading = false }

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            let ref = storage.reference(withPath: "users/\(normalizedUID)/profile/photo.jpg")
            _ = try await ref.putDataAsync(processedData, metadata: metadata)
            let url = try await ref.downloadURL()
            return url.absoluteString
        } catch {
            // Fallback for legacy builds that used users/{uid}/photo.jpg.
            do {
                let legacyRef = storage.reference(withPath: "users/\(normalizedUID)/photo.jpg")
                _ = try await legacyRef.putDataAsync(processedData, metadata: metadata)
                let url = try await legacyRef.downloadURL()
                return url.absoluteString
            } catch {
                lastErrorMessage = error.localizedDescription
                return nil
            }
        }
    }

    func deleteProfilePhoto(uid: String) async {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else { return }
        let refs = [
            storage.reference(withPath: "users/\(normalizedUID)/profile/photo.jpg"),
            storage.reference(withPath: "users/\(normalizedUID)/photo.jpg")
        ]
        for ref in refs {
            do {
                try await ref.delete()
            } catch {
                // Best-effort cleanup.
            }
        }
    }

    private static func prepareUploadImageData(from image: UIImage) -> Data? {
        guard let square = cropSquare(image: image) else { return nil }
        let resized = resize(image: square, maxSide: 640)
        return resized.jpegData(compressionQuality: 0.82)
    }

    private static func cropSquare(image: UIImage) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let side = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))

        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func resize(image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = min(max(image.size.width, image.size.height), maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
