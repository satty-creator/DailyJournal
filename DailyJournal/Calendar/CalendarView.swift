//
//  CalendarView.swift
//  DailyJournal
//
//  Phase 1 — a read-only month/day view of the user's primary Google
//  Calendar, opened from HomeView's header icon. View-only: no AI usage yet
//  (see CalendarService.swift's header comment for what's deferred).
//

import SwiftUI

struct CalendarView: View {
    @StateObject private var vm = CalendarViewModel()
    @Environment(\.dismiss) private var dismiss
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                switch vm.status {
                case .connected:
                    connectedContent
                case .notConnected, .scopeDenied:
                    notConnectedContent
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            vm.refreshStatus()
            if vm.status == .connected {
                await vm.loadMonth()
            }
        }
    }

    // MARK: - Not connected / scope denied
    private var notConnectedContent: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.terracotta)
            VStack(spacing: 8) {
                Text("Connect Google Calendar")
                    .font(AppTheme.editorialDisplay(size: 22))
                    .foregroundStyle(AppTheme.ink)
                Text(
                    vm.status == .scopeDenied
                        ? "Calendar access was declined or revoked. Reconnect to view your events here."
                        : "See your day at a glance, right inside Spilr. Read-only \u{2014} Spilr never edits or creates events."
                )
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            }
            Button {
                Task { await vm.connect() }
            } label: {
                Text("Connect")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.cream)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.terracotta.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Connected
    private var connectedContent: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            monthGrid
                .padding(.horizontal, 16)
            Divider()
                .padding(.vertical, 12)
            dayDetail
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var monthHeader: some View {
        HStack {
            Button { vm.goToPreviousMonth() } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(AppTheme.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(vm.displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(AppTheme.editorialDisplay(size: 18))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Button { vm.goToNextMonth() } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(Array(shortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var shortWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
    }

    /// One entry per grid cell for the displayed month: leading blanks to
    /// align the 1st onto the correct weekday column, then every day.
    private var gridDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: vm.displayedMonth) else { return [] }
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                days.append(date)
            }
        }
        return days
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: vm.selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasEvents = !(vm.eventsByDay[calendar.startOfDay(for: day)] ?? []).isEmpty

        return Button {
            withAnimation(.easeOut(duration: 0.15)) { vm.selectedDay = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 14, weight: isToday ? .heavy : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? AppTheme.cream : AppTheme.ink)
                Circle()
                    .fill(hasEvents ? (isSelected ? AppTheme.cream : AppTheme.terracotta) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isSelected ? AnyShapeStyle(AppTheme.terracotta) : AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.terracotta, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var dayDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(vm.selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1.2)
                    .padding(.horizontal, 24)

                if vm.isLoading {
                    ProgressView()
                        .padding(.horizontal, 24)
                } else if vm.loadError {
                    errorRow
                } else if vm.selectedDayEvents.isEmpty {
                    Text("Nothing on the calendar this day.")
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.inkSoft)
                        .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.selectedDayEvents) { event in
                            eventRow(event)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var errorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load your calendar.")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
            Button("Retry") {
                Task { await vm.loadMonth() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.terracotta)
        }
        .padding(.horizontal, 24)
    }

    private func eventRow(_ event: CalendarService.CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.isAllDay ? "ALL DAY" : event.start.formatted(.dateTime.hour().minute()))
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(AppTheme.terracotta)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
