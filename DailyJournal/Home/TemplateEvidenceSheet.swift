//
//  TemplateEvidenceSheet.swift
//  DailyJournal
//
//  "Why these?" — separates the clinical/research evidence behind some
//  templates from the product-adoption pattern behind the rest, and replaces
//  the unsupported "written with licensed therapists" claim the gallery used
//  to make. Structure borrowed from `StartOptionsView` / `FutureSelfSheet`
//  (grabber capsule, eyebrow, display headline).
//

import SwiftUI

struct TemplateEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var clinical: [TemplateEvidence] {
        TemplateEvidenceLibrary.all.filter { $0.kind == .clinical }
    }
    private var practice: [TemplateEvidence] {
        TemplateEvidenceLibrary.all.filter { $0.kind == .practice }
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Capsule()
                        .fill(AppTheme.inkSoft.opacity(0.2))
                        .frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 18)

                    Text("Why these?")
                        .font(AppTheme.editorialDisplay(size: 24))
                        .foregroundStyle(AppTheme.ink)

                    Text("Some exercises follow a published framework or study. Others are a widely-used writing pattern with no clinical trial behind them \u{2014} we say which is which.")
                        .font(AppTheme.editorialBody(size: 13.5))
                        .foregroundStyle(AppTheme.inkSoft)
                        .lineSpacing(3)
                        .padding(.top, 6)

                    section(title: "Clinical & research evidence", items: clinical)
                        .padding(.top, 24)

                    section(title: "Product pattern \u{2014} not a therapy claim", items: practice)
                        .padding(.top, 24)

                    Text("Spilr is not a therapist, and these exercises are not treatment.")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.slate)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 22)
            }
        }
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
    }

    private func section(title: String, items: [TemplateEvidence]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(AppTheme.mono(size: 11))
                .tracking(1.5)
                .foregroundStyle(AppTheme.inkSoft)

            ForEach(items) { evidence in
                VStack(alignment: .leading, spacing: 6) {
                    Text(evidence.pill)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(evidence.blurb)
                        .font(AppTheme.editorialBody(size: 12.5))
                        .foregroundStyle(AppTheme.inkSoft)
                        .lineSpacing(2)
                    if !evidence.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(evidence.sources) { source in
                                Link(source.label, destination: source.url)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.lavDeep)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(cornerRadius: 16, padding: 14)
            }
        }
    }
}
