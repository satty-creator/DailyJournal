//
//  PhotoUploadService.swift
//  DailyJournal
//
//  Uploads an entry's attached photo to Firebase Storage and returns its public
//  download URL. There is no custom server: Storage is a Google-managed bucket
//  and this Swift code talks to it directly via the FirebaseStorage SDK.
//
//  Storage layout: users/{uid}/entryPhotos/{entryId}.jpg
//  (mirrors the Firestore layout users/{uid}/entries/{entryId}). Access is
//  locked to the owning user by storage.rules.
//
//  Photos are always re-encoded to JPEG and downscaled before upload so a
//  full-resolution camera image never balloons a journal entry.
//

import Foundation
import UIKit
import FirebaseStorage

final class PhotoUploadService {

    static let shared = PhotoUploadService()
    private init() {}

    private let storage = Storage.storage()

    /// Max longest-edge in points before upload. Keeps uploads small + fast.
    private let maxDimension: CGFloat = 1600
    private let jpegQuality: CGFloat = 0.7

    /// Uploads `image` for the given entry and returns the download URL string.
    /// Returns nil on any failure — callers treat photos as best-effort, never
    /// blocking the save.
    ///
    /// The failure is NOT silent, even though the return value still is (by
    /// design — a failed upload must never surface as a blocking error). A denied
    /// Storage write (e.g. `storage.rules` not deployed for the current Firebase
    /// project) and a dead download URL previously looked identical to the user:
    /// "the photo just never shows up," with nothing in the logs to tell them
    /// apart. This makes the failure diagnosable via `trackError` without
    /// changing the fire-and-forget contract callers rely on.
    func uploadEntryPhoto(_ image: UIImage, userId: String, entryId: String) async -> String? {
        guard let data = jpegData(from: image) else {
            await AnalyticsManager.shared.trackError(
                NSError(domain: "PhotoUploadService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to encode image to JPEG"]),
                context: "photo_upload_encode"
            )
            return nil
        }

        let ref = storage.reference()
            .child("users/\(userId)/entryPhotos/\(entryId).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        do {
            _ = try await ref.putDataAsync(data, metadata: meta)
            let url = try await ref.downloadURL()
            await AnalyticsManager.shared.logEvent(.photoAdded)
            return url.absoluteString
        } catch {
            #if DEBUG
            print("PhotoUploadService: upload failed for entry \(entryId) — \(error)")
            #endif
            await AnalyticsManager.shared.trackError(error, context: "photo_upload")
            return nil
        }
    }

    /// Deletes the photo for an entry (best-effort; ignored if none exists).
    func deleteEntryPhoto(userId: String, entryId: String) {
        storage.reference()
            .child("users/\(userId)/entryPhotos/\(entryId).jpg")
            .delete(completion: nil)
    }

    // MARK: - Downscale + encode

    private func jpegData(from image: UIImage) -> Data? {
        let scaled = downscaled(image)
        return scaled.jpegData(compressionQuality: jpegQuality)
    }

    private func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let factor = maxDimension / longest
        let newSize = CGSize(width: image.size.width * factor,
                             height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
