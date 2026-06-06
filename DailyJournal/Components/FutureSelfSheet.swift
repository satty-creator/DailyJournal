//
//  FutureSelfSheet.swift
//  DailyJournal
//
//  Post-save sheet: choose when to deliver this entry to future-you.
//

import SwiftUI
import UserNotifications

struct FutureSelfSheet: View {

    let entry: JournalEntry
    let onScheduled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: DeliveryOption = .oneMonth
    @State private var isScheduling = false
    @State private var done = false

    private let service = JournalService()

    enum DeliveryOption: CaseIterable, Identifiable {
        case twoWeeks, oneMonth, threeMonths, oneYear

        var id: Self { self }

        var label: String {
            switch self {
            case .twoWeeks:     return "2 weeks"
            case .oneMonth:     return "1 month"
            case .threeMonths:  return "3 months"
            case .oneYear:      return "1 year"
            }
        }

        var subLabel: String {
            switch self {
            case .twoWeeks:    return "Quick check-in"
            case .oneMonth:    return "Monthly reflection"
            case .threeMonths: return "Season later"
            case .oneYear:     return "Future you"
            }
        }

        var deliveryDate: Date {
            let cal = Calendar.current
            switch self {
            case .twoWeeks:    return cal.date(byAdding: .weekOfYear, value: 2,  to: Date())!
            case .oneMonth:    return cal.date(byAdding: .month,      value: 1,  to: Date())!
            case .threeMonths: return cal.date(byAdding: .month,      value: 3,  to: Date())!
            case .oneYear:     return cal.date(byAdding: .year,       value: 1,  to: Date())!
            }
        }
    }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            if done {
                successView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                mainContent
            }
        }
        .animation(.spring(response: 0.45), value: done)
    }

    // MARK: - Main content
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Handle
            Capsule()
                .fill(AppTheme.inkSoft.opacity(0.2))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("SEND TO FUTURE YOU")
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(2)

                Text("Your entry will arrive as a letter\nwhen you need it most.")
                    .font(AppTheme.editorialDisplay(size: 24))
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)

            // Entry preview
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(AppTheme.terracotta)
                    .frame(width: 3)
                    .clipShape(Capsule())

                Text(String(entry.content.prefix(120)) + (entry.content.count > 120 ? "…" : ""))
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(3)
                    .italic()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            // Delivery options
            VStack(spacing: 10) {
                ForEach(DeliveryOption.allCases) { option in
                    deliveryOptionRow(option)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            // Schedule button
            Button {
                Task { await schedule() }
            } label: {
                HStack {
                    if isScheduling {
                        ProgressView()
                            .tint(AppTheme.cream)
                    } else {
                        Text("Seal and send →")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isScheduling)
            .padding(.horizontal, 20)

            Button("Not now") { dismiss() }
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Delivery option row
    private func deliveryOptionRow(_ option: DeliveryOption) -> some View {
        Button { selectedOption = option } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Text(option.subLabel)
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(0.5)
                }
                Spacer()
                Text(option.deliveryDate.formatted(.dateTime.month(.wide).day().year()))
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)

                ZStack {
                    Circle()
                        .stroke(selectedOption == option ? AppTheme.terracotta : AppTheme.inkSoft.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if selectedOption == option {
                        Circle()
                            .fill(AppTheme.terracotta)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                selectedOption == option
                    ? AppTheme.terracotta.opacity(0.07)
                    : AppTheme.cream
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedOption == option ? AppTheme.terracotta.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Success view
    private var successView: some View {
        VStack(spacing: 20) {
            Text("✉")
                .font(.system(size: 64))

            Text("Sealed.")
                .font(AppTheme.editorialDisplay(size: 36))
                .foregroundStyle(AppTheme.ink)

            Text("Your letter is on its way to \(selectedOption.label) from now.\nYou'll get a notification when it arrives.")
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Text(selectedOption.deliveryDate.formatted(.dateTime.month(.wide).day().year()))
                .font(AppTheme.mono(size: 12))
                .foregroundStyle(AppTheme.terracotta)
                .tracking(1)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                onScheduled()
                dismiss()
            }
        }
    }

    // MARK: - Schedule action
    private func schedule() async {
        isScheduling = true

        let deliveryDate = selectedOption.deliveryDate

        // 1. Write to Firestore — fire-and-forget (local cache write, background server sync)
        service.scheduleFutureSelf(
            entryId: entry.id,
            userId: entry.userId,
            deliveryDate: deliveryDate
        )

        // 2. Schedule a local push notification so the letter actually arrives
        await scheduleNotification(entryId: entry.id, deliveryDate: deliveryDate)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { done = true }
        isScheduling = false
    }

    // MARK: - Local notification
    private func scheduleNotification(entryId: String, deliveryDate: Date) async {
        let center = UNUserNotificationCenter.current()

        // Request authorisation if not yet determined
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true else {
                return
            }
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        // Build the notification content
        let content = UNMutableNotificationContent()
        content.title = "A letter from past you"
        let preview = String(entry.content.prefix(120))
        content.body = preview.count < entry.content.count ? preview + "…" : preview
        content.sound = .default
        content.userInfo = ["entryId": entryId]

        // Fire at the delivery date (date + time preserved, no repeat)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: deliveryDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "letter-\(entryId)", content: content, trigger: trigger)

        try? await center.add(request)
    }
}
