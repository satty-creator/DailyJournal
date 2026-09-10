//
//  ThisWeekStripView.swift
//  DailyJournal
//
//  "This week, in your words" — mirror-v3-prd-2026-09-10.md §5.3.
//
//  Three Tier-0 facts. No model, no thresholds, available from the very first
//  entry. This is the part of Mirror that is never empty and never wrong,
//  which is what buys the interpretation above it any credibility at all.
//
//  Rows are NOT tappable in v3.0 — §5.3 wants each row to open the entries it
//  counts, which needs a filtered journal list that doesn't exist yet. A row
//  that looks tappable and does nothing is worse than one that doesn't.
//

import SwiftUI

struct ThisWeekStripView: View {

    let facts: MirrorFacts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("this week, in your words")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1.2)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().overlay(AppTheme.inkSoft.opacity(0.12)) }
                    factRow(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 22, padding: 18)
    }

    // MARK: - Row model

    /// A row is a bolded quantity plus the plain-language rest of the sentence,
    /// so the NUMBER is what the eye lands on first (§3 principle 1: a number,
    /// a date or a verbatim phrase is on screen before anything that
    /// interprets it).
    private struct Row {
        let lead: String
        let rest: String
    }

    private func factRow(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.lead)
                .font(AppTheme.editorialDisplay(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text(row.rest)
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    /// A fixed rotation, so the strip is never empty: cadence, then the
    /// repeated word, then people. Each row degrades to something true rather
    /// than disappearing.
    private var rows: [Row] {
        let week = facts.week
        var out: [Row] = [cadenceRow]

        if let emotion = week.topEmotion, emotion.count >= 2 {
            var rest = "— \(emotion.count) times"
            if let cluster = emotion.clusterLabel {
                rest += ", all on \(cluster) days"
            }
            out.append(Row(lead: "'\(emotion.word)'", rest: rest))
        } else if let phrase = week.topPhrases.first, phrase.count >= 2 {
            out.append(Row(lead: "'\(phrase.label)'", rest: "— \(phrase.count) times"))
        }

        if !week.people.isEmpty {
            let named = week.people.prefix(3)
                .map { "\($0.label) \($0.count)" }
                .joined(separator: " · ")
            out.append(Row(lead: named, rest: ""))
        } else if !week.roles.isEmpty {
            // Fallback while `people` coverage is still zero — entries analysed
            // before mirror-extract-v2 carry role words but no names.
            let roles = week.roles.prefix(2).map { "\($0.label) ×\($0.count)" }.joined(separator: " · ")
            out.append(Row(lead: roles, rest: "— the part you played"))
        } else if let domain = week.topDomains.first {
            out.append(Row(lead: domain.label, rest: "in \(domain.count) of \(week.entries)"))
        }

        return out
    }

    /// "4 entries · 3 after 9pm", or the honest one-entry version with the
    /// unlock hint attached (§5.3's own example).
    private var cadenceRow: Row {
        let week = facts.week
        if week.entries == 0 {
            return Row(lead: "No entries yet", rest: "this week")
        }
        if week.entries == 1 {
            var rest = "this week"
            if let band = week.dominantBand {
                rest = "· \(ThisWeekStripView.bandPhrase(band.band))"
            }
            if let hint = facts.unlock.hint {
                rest += ". \(hint)"
            }
            return Row(lead: "1 entry", rest: rest)
        }
        var rest = ""
        if week.lateEntries > 0 {
            rest = "· \(week.lateEntries) after 9pm"
        } else if let band = week.dominantBand, band.count > 1 {
            rest = "· \(band.count) \(ThisWeekStripView.bandPhrase(band.band))"
        } else if week.activeDays != week.entries {
            rest = "across \(week.activeDays) days"
        }
        return Row(lead: "\(week.entries) entries", rest: rest)
    }

    static func bandPhrase(_ band: String) -> String {
        switch band {
        case "morning":   return "before noon"
        case "afternoon": return "in the afternoon"
        case "evening":   return "in the evening"
        case "late":      return "after 9pm"
        default:          return band
        }
    }
}
