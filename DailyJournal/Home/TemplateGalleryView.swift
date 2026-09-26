//
//  TemplateGalleryView.swift
//  DailyJournal
//
//  The "Templates" gallery, presented as a sheet from the invitation card's
//  "Templates" chip on Home.
//
//  Cards are tappable: picking one hands the template back to `onStart`,
//  which `HomeView` uses to stash the pick and present `TemplateRunnerView`
//  once this sheet has finished dismissing.
//

import SwiftUI

struct TemplateGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (JournalTemplate) -> Void

    @State private var showEvidenceSheet = false
    private let filters = ["For you", "Calm", "Clarity", "Sleep"]
    @State private var selectedFilter = "For you"

    /// "For you" isn't a real recommendation — there's no signal to rank on
    /// yet — so it's simply the unfiltered catalog. The other three chips
    /// filter for real against each template's `tags`.
    private var filtered: [JournalTemplate] {
        selectedFilter == "For you"
            ? JournalTemplate.all
            : JournalTemplate.all.filter { $0.tags.contains(selectedFilter.lowercased()) }
    }

    /// The wide featured card. Re-derived from the active filter (falling
    /// back to the filtered set's first item) rather than pinned, so it
    /// never shows a template the current filter would otherwise exclude.
    private var featured: JournalTemplate? {
        filtered.first { $0.isFeatured } ?? filtered.first
    }

    private var gridTemplates: [JournalTemplate] {
        filtered.filter { $0.id != featured?.id }
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    filterRow

                    VStack(spacing: 11) {
                        if filtered.isEmpty {
                            emptyFilterState
                        } else {
                            if let featured {
                                featuredCard(featured)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible())], spacing: 11) {
                                ForEach(gridTemplates) { template in
                                    gridCard(template)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)

                    Text("Each exercise follows a published framework \u{00b7} you can leave any question blank")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.slate)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                        .padding(.bottom, 28)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showEvidenceSheet) {
            TemplateEvidenceSheet()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 4) {
                Text("Templates")
                    .font(AppTheme.editorialDisplay(size: 23))
                    .foregroundStyle(AppTheme.ink)
                Text("Short, structured exercises. Each one names its source.")
                    .font(AppTheme.editorialBody(size: 12.5))
                    .foregroundStyle(AppTheme.inkSoft)
            }

            Spacer(minLength: 0)

            Button { showEvidenceSheet = true } label: {
                Text("Why these?")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.cream)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Filter chips

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    let selected = filter == selectedFilter
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selectedFilter = filter }
                    } label: {
                        Text(filter)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? AppTheme.cream : AppTheme.inkSoft)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selected ? AppTheme.ink : AppTheme.cream)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(AppTheme.inkSoft.opacity(selected ? 0 : 0.16), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // MARK: - Empty state (latent today — no current filter yields zero
    // templates — but the filter chips and `tags` are otherwise unrelated
    // data, so nothing guarantees that stays true.)

    private var emptyFilterState: some View {
        VStack(spacing: 6) {
            Text("No exercises match yet")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text("Try a different filter.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Cards

    private func featuredCard(_ template: JournalTemplate) -> some View {
        Button { onStart(template) } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(template.accentColor)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(template.blurb)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                    HStack(spacing: 6) {
                        templateMeta(template)
                        evidencePill(template)
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft.opacity(0.5))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func gridCard(_ template: JournalTemplate) -> some View {
        Button { onStart(template) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Circle()
                    .fill(template.accentColor)
                    .frame(width: 28, height: 28)
                Text(template.title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
                Text(template.blurb)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                templateMeta(template)
                    .padding(.top, 5)
                evidencePill(template)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.inkSoft.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func templateMeta(_ template: JournalTemplate) -> some View {
        Text("\(template.stepCount) STEPS \u{00b7} ~\(template.minutes) MIN")
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(AppTheme.slate)
    }

    /// Clinical vs. practice pill — the gallery-level cue for the same split
    /// the "Why these?" sheet spells out in full.
    private func evidencePill(_ template: JournalTemplate) -> some View {
        let isClinical = template.evidence.kind == .clinical
        return Text(isClinical ? "EVIDENCE-BASED" : "PRACTICE PATTERN")
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(isClinical ? AppTheme.moss : AppTheme.dusk)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((isClinical ? AppTheme.mint : AppTheme.peach).opacity(0.3))
            .clipShape(Capsule())
    }
}
