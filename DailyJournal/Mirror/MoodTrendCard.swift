//
//  MoodTrendCard.swift
//  DailyJournal
//
//  A small 0–10 line chart of `MoodLogPoint`s — onboarding's baseline and
//  every guided entry's before/after ratings, going forward. Placed on the
//  Mirror tab (`SelfModelView`) above the profile sections; hidden below 2
//  points, since one dot isn't a trend.
//
//  Labels and axes only — no generated copy, no interpretation of the shape.
//  "No local text in Spilr's voice" (CLAUDE.md) applies here too: a line
//  chart of the user's own numbers is data, not an observation about them.
//

import SwiftUI
import Charts

struct MoodTrendCard: View {
    let points: [MoodLogPoint]

    private var latest: MoodLogPoint? { points.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("HOW HEAVY THINGS FEEL")
                    .font(AppTheme.mono(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.inkSoft)
                Spacer()
                if let latest {
                    Text("\(latest.value)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.valenceColor(latest.value / 2 - 3))
                }
            }

            Chart(points.indices, id: \.self) { i in
                let point = points[i]
                LineMark(
                    x: .value("When", point.at),
                    y: .value("Heaviness", point.value)
                )
                .foregroundStyle(AppTheme.lavDeep)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("When", point.at),
                    y: .value("Heaviness", point.value)
                )
                .foregroundStyle(AppTheme.valenceColor(point.value / 2 - 3))
                .symbolSize(28)
            }
            .chartYScale(domain: 0...10)
            .chartYAxis {
                AxisMarks(values: [0, 5, 10])
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(AppTheme.mono(size: 9))
                }
            }
            .frame(height: 120)
        }
        .softCard(cornerRadius: 22, padding: 16)
    }
}
