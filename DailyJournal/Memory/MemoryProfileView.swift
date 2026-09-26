//
//  MemoryProfileView.swift
//  DailyJournal
//
//  "What Spilr remembers" — the MemoryProfile, shown to the person it is about.
//
//  This digest is appended to every AI prompt the app builds (chat, echo
//  extraction, entry insights, the template weave, and the Mirror's own entry
//  analysis), and until this screen existed there was no way to see it, and no
//  way to remove anything from it. That is a strange asymmetry in an app whose
//  Mirror tab lets you correct every hypothesis it forms about you.
//
//  Two rules carried over from SelfModelView, which solved the same problem for
//  the hypothesis layer:
//    • No numeric confidence. A count and a plain sentence about where the item
//      came from; nothing dressed up as a measurement.
//    • Forgetting is one tap and it sticks. `MemoryProfileService.forget` writes
//      to a suppression list the rebuild reads, because `compose` is
//      deterministic and would otherwise resurrect the item within the minute.
//

import SwiftUI

struct MemoryProfileView: View {

    let userId: String

    @State private var profile: MemoryProfile = .empty
    @State private var forgottenCount = 0
    @Environment(\.dismiss) private var dismiss

    private var sections: [(kind: MemoryProfile.ItemKind, items: [MemoryProfile.Item])] {
        MemoryProfile.ItemKind.allCases.compactMap { kind in
            let items = profile.items.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if sections.isEmpty {
                        emptyState
                    } else {
                        ForEach(sections, id: \.kind) { section in
                            sectionView(section.kind, items: section.items)
                        }
                    }

                    if forgottenCount > 0 { restoreRow }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("What Spilr remembers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This is everything Spilr carries into a conversation about you. It is counted from your own entries — nothing here came from anywhere else.")
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if profile.hasContent {
                Text("Updated \(profile.generatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing yet.")
                .font(AppTheme.editorialDisplay(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("A word has to appear in three entries, and a phrase twice, before it is kept. Until then Spilr goes in with nothing.")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    private func sectionView(_ kind: MemoryProfile.ItemKind, items: [MemoryProfile.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.sectionTitle)
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
                .textCase(.uppercase)

            Text(kind.provenance)
                .font(AppTheme.editorialBody(size: 13))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(items) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: MemoryProfile.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let count = item.count {
                    Text(countLabel(item.kind, count))
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }

            Spacer(minLength: 8)

            Button {
                MemoryProfileService.shared.forget(item, for: userId)
                withAnimation(.easeOut(duration: 0.2)) {
                    profile = profile.removing([item.id])
                    forgottenCount += 1
                }
            } label: {
                Text("Forget")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func countLabel(_ kind: MemoryProfile.ItemKind, _ count: Int) -> String {
        switch kind {
        case .theme: return count == 1 ? "in 1 entry" : "in \(count) entries"
        default:     return count == 1 ? "said once" : "said \(count) times"
        }
    }

    private var restoreRow: some View {
        Button {
            MemoryProfileService.shared.restoreForgotten(for: userId)
            forgottenCount = 0
            Task { await reload(force: true) }
        } label: {
            Text("Bring back what I removed")
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func reload(force: Bool = false) async {
        guard !userId.isEmpty else { return }
        profile = await MemoryProfileService.shared.build(for: userId, force: force)
        forgottenCount = MemoryProfileService.shared.suppressedKeys(for: userId).count
    }
}
