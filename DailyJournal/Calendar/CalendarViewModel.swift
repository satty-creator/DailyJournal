//
//  CalendarViewModel.swift
//  DailyJournal
//

import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var displayedMonth: Date
    @Published var selectedDay: Date
    @Published private(set) var eventsByDay: [Date: [CalendarService.CalendarEvent]] = [:]
    @Published private(set) var status: CalendarService.Status
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: Bool = false

    private let calendar = Calendar.current

    init() {
        let today = Date()
        displayedMonth = today
        selectedDay = today
        status = CalendarService.shared.currentStatus()
    }

    /// Events for the currently selected day, sorted by start time.
    var selectedDayEvents: [CalendarService.CalendarEvent] {
        eventsByDay[calendar.startOfDay(for: selectedDay)] ?? []
    }

    func refreshStatus() {
        status = CalendarService.shared.currentStatus()
    }

    func connect() async {
        let connected = await CalendarService.shared.connect()
        refreshStatus()
        AnalyticsManager.shared.logEvent(connected ? .calendarConnected : .calendarConsentDeclined)
        if connected {
            await loadMonth()
        }
    }

    func disconnect() {
        CalendarService.shared.disconnect()
        refreshStatus()
        eventsByDay = [:]
        AnalyticsManager.shared.logEvent(.calendarDisconnected)
    }

    func goToPreviousMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        displayedMonth = newMonth
        Task { await loadMonth() }
    }

    func goToNextMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        displayedMonth = newMonth
        Task { await loadMonth() }
    }

    func loadMonth() async {
        refreshStatus()
        guard status == .connected else { return }

        isLoading = true
        loadError = false
        defer { isLoading = false }

        do {
            let events = try await CalendarService.shared.fetchEvents(monthContaining: displayedMonth)
            eventsByDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) }
        } catch {
            loadError = true
            refreshStatus()
        }
    }
}
