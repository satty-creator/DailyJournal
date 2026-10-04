//
//  PhotoCacheService.swift
//  DailyJournal
//
//  A just-picked photo is shown in the editor instantly (from the in-memory
//  UIImage) but list/collage only ever render `entry.photoURL`, which is
//  nil until PhotoUploadService's detached upload finishes. This closes that
//  gap: EntryEnrichment stores the picked image here, keyed by entryId, the
//  moment a save happens, so any surface already showing that entry can
//  render the real photo immediately instead of a placeholder tile/blank
//  space. Once the upload lands, `photoURL` takes over and AsyncImage takes
//  the same image from Storage — this is a first-paint cache, not the
//  source of truth.
//

import Foundation
import UIKit

final class PhotoCacheService {

    static let shared = PhotoCacheService()
    private init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private let memory = NSCache<NSString, UIImage>()

    private let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EntryPhotos", isDirectory: true)
    }()

    private func fileURL(for entryId: String) -> URL {
        directory.appendingPathComponent("\(entryId).jpg")
    }

    /// Caches `image` for `entryId` so it can be shown before the Storage
    /// upload completes. The memory cache is warm immediately (synchronous);
    /// the disk write is dispatched off-thread so this never blocks a save.
    func store(_ image: UIImage, forEntryId entryId: String) {
        memory.setObject(image, forKey: entryId as NSString)
        let url = fileURL(for: entryId)
        DispatchQueue.global(qos: .utility).async {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// A cheap existence check — used by CollageTileKind to classify a tile
    /// as `.photo` before `photoURL` exists, without decoding the image.
    func hasImage(forEntryId entryId: String) -> Bool {
        if memory.object(forKey: entryId as NSString) != nil { return true }
        return FileManager.default.fileExists(atPath: fileURL(for: entryId).path)
    }

    func image(forEntryId entryId: String) -> UIImage? {
        if let cached = memory.object(forKey: entryId as NSString) { return cached }
        guard let data = try? Data(contentsOf: fileURL(for: entryId)),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: entryId as NSString)
        return image
    }
}
