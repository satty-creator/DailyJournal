//
//  PhotoAttachCard.swift
//  DailyJournal
//
//  The "Add a moment" photo card, shared by every composer that can attach a
//  photo to an entry: the blank page (`SpillWriteView`), Daily Chat's woven
//  preview (`WovenEntryPreviewSheet`) and the template review
//  (`TemplateReviewView`). It only picks and previews locally — the owning
//  ViewModel hands the image to `EntryEnrichment.run(photo:)` on save, which
//  uploads it detached. The photo is never sent to the AI.
//

import SwiftUI
import PhotosUI
import UIKit

struct PhotoAttachCard: View {

    @Binding var image: UIImage?

    /// Owned here rather than by callers — they only care about the decoded
    /// image. Reset on clear so re-picking the same photo still fires onChange.
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text("Add a moment")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("A photo makes the memory richer. Sharing stays opt-in.")
                    .font(AppTheme.editorialBody(size: 12))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(image == nil ? "Upload" : "Change")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.cream.opacity(0.8))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
            }
            .accessibilityIdentifier("photoAttach.pick")
        }
        .padding(11)
        .background(AppTheme.terracotta.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.terracotta.opacity(0.42),
                              style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
        )
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    image = ui
                }
            }
        }
    }

    private var thumbnail: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [AppTheme.terracotta.opacity(0.26), AppTheme.sun.opacity(0.26)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if image != nil {
                Button {
                    image = nil
                    pickerItem = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.cream)
                        .frame(width: 20, height: 20)
                        .background(AppTheme.ink.opacity(0.75))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove photo")
                .accessibilityIdentifier("photoAttach.remove")
            }
        }
    }
}
