//
//  EvidenceDrawerView.swift
//  DailyJournal
//
//  A full sheet-style view showing all evidence behind a PatternHypothesis.
//  Present as .sheet from any parent that holds a PatternHypothesis.
//

import SwiftUI

struct EvidenceDrawerView: View {

    let hypothesis: PatternHypothesis
    /// The daily card this hypothesis produced, when opened from Today's
    /// Mirror — supplies the L2 fields the card doc carries that the
    /// hypothesis doesn't (`possibleRead`, `tinyExperiment` as written by the
    /// proof writer). Nil when opened from the pattern list, where only the
    /// hypothesis exists; the deterministic fallbacks below (`hypothesis.cost`
    /// as the alternative read source, `hypothesis.tinyExperiment`) cover
    /// that case so L2 is never empty.
    var card: MirrorCard? = nil
    let onDismiss: () -> Void
    var onCorrect: ((PatternHypothesis) -> Void)? = nil
    var onHide: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showCorrectionInput = false
    @State private var correctionText = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private var confidenceLabel: String {
        if hypothesis.salienceScore < 0.4 { return "low" }
        if hypothesis.salienceScore < 0.7 { return "medium" }
        return "high"
    }

    private var confidenceColor: Color {
        if hypothesis.salienceScore < 0.4 { return AppTheme.slate }
        if hypothesis.salienceScore < 0.7 { return AppTheme.peach }
        return AppTheme.terracotta
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        statsSection
                        evidenceSection
                        if !hypothesis.counterEvidence.isEmpty {
                            counterEvidenceSection
                        }
                        if hypothesis.protection != nil || hypothesis.cost != nil {
                            patternFormulaCard
                        }
                        if let possibleRead {
                            possibleReadSection(possibleRead)
                        }
                        if let tinyExperiment {
                            tinyExperimentSection(tinyExperiment)
                        }
                        actionButtons
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Why Spilr thinks this")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                AnalyticsManager.shared.logEvent(.patternEvidenceViewed)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.terracotta)
                }
            }
        }
    }

    // MARK: - Stats section

    private var statsSection: some View {
        HStack(spacing: 10) {
            statsCell(value: "\(hypothesis.timesSeen)", label: "Times seen")
            statsCell(
                value: dateFormatter.string(from: hypothesis.firstSeenAt),
                label: "First seen"
            )
            statsCell(value: confidenceLabel, label: "Confidence", color: confidenceColor)
        }
    }

    private func statsCell(value: String, label: String, color: Color = AppTheme.ink) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTheme.editorialDisplay(size: 17, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .softCard(cornerRadius: 18, padding: 10)
    }

    // MARK: - Evidence section

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Supporting receipts")

            ForEach(hypothesis.evidence.prefix(4)) { item in
                evidenceCard(for: item)
            }

            if hypothesis.evidence.isEmpty {
                Text("No individual quotes on file — pattern was inferred from signals across entries.")
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
                    .italic()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.paperWarm.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func evidenceCard(for item: PatternEvidence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.entryCreatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                Spacer()
            }

            Text("\u{201C}\(item.quote)\u{201D}")
                .font(AppTheme.editorialBody(size: 15.5).italic())
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .softCard(cornerRadius: 18, padding: 14)
    }

    // MARK: - Counter evidence section

    private var counterEvidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("The other side")

            ForEach(Array(hypothesis.counterEvidence.prefix(3).enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.mint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                AppTheme.mint.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                            )
                    )
            }
        }
    }

    // MARK: - Pattern formula card

    private var patternFormulaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("The pattern formula")

            VStack(alignment: .leading, spacing: 8) {
                formulaLine(label: "When", value: hypothesis.archetype.displayLabel)
                formulaLine(label: "You often", value: hypothesis.userFacingTitle)
                if let protection = hypothesis.protection {
                    formulaLine(label: "Which may help you", value: protection)
                }
                if let cost = hypothesis.cost {
                    formulaLine(label: "But may cost", value: cost)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.lav.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.lav.opacity(0.4), lineWidth: 1)
            )
        }
    }

    // MARK: - Possible read ("or, it might be…")

    /// The card-written alternative interpretation if the proof writer
    /// produced one; otherwise the counter-evidence pass's first finding —
    /// exactly what it exists to feed. Empty only when neither source has
    /// anything, which the section itself gates on.
    private var possibleRead: String? {
        if let read = card?.possibleRead, !read.isEmpty { return read }
        return hypothesis.counterEvidence.first
    }

    private func possibleReadSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Or, it might be")
            Text(text)
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.paperWarm.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Tiny experiment

    private var tinyExperiment: String? {
        card?.tinyExperiment ?? hypothesis.tinyExperiment
    }

    private func tinyExperimentSection(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.rose.opacity(0.2))
                    .frame(width: 34, height: 34)
                Image(systemName: "flask")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("tiny experiment")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                    .textCase(.uppercase)
                Text(text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppTheme.paperWarm.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formulaLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(0.5)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(AppTheme.editorialDisplay(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if showCorrectionInput {
                correctionInputSection
            } else {
                Button {
                    withAnimation { showCorrectionInput = true }
                } label: {
                    Text("Correct this")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }

            Button {
                onHide?(hypothesis.id)
                onDismiss()
                dismiss()
            } label: {
                Text("Hide from profile")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var correctionInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What would you correct?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            TextField("e.g. This isn't about fear, it's about...", text: $correctionText, axis: .vertical)
                .font(AppTheme.editorialBody(size: 14))
                .lineLimit(2...5)
                .padding(12)
                .background(AppTheme.cream.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.inkSoft.opacity(0.2), lineWidth: 1))

            HStack(spacing: 10) {
                Button {
                    let trimmed = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Behaviour ("stop asking so many questions") routes to
                    // StylePreferences, not ProfileCorrection — it's feedback
                    // about HOW Spilr writes, not evidence the hypothesis
                    // itself is wrong, so it shouldn't retire or exclude it.
                    if MirrorCorrectionClassifier.isStyleCorrection(trimmed) {
                        StylePreferencesService.shared.addNote(trimmed, userId: hypothesis.userId)
                    } else {
                        let correction = ProfileCorrection(
                            userId: hypothesis.userId,
                            feedbackType: .notMe,
                            hypothesisId: hypothesis.id,
                            userCorrection: correctionText
                        )
                        SelfModelService.shared.submitCorrection(correction, userId: hypothesis.userId)
                    }
                    onCorrect?(hypothesis)
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Submit")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.cream)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.terracotta)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                Button {
                    withAnimation { showCorrectionInput = false }
                    correctionText = ""
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppTheme.paperWarm.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(1.2)
    }
}
