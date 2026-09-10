//
//  ScreenTrackingModifier.swift
//  DailyJournal
//
//  ViewModifier to automatically track screen views with onAppear/onDisappear.
//  Usage: MyView().trackScreen(.home)

import SwiftUI

struct ScreenTrackingModifier: ViewModifier {
    let screen: AnalyticsScreen
    let parameters: [String: Any]?

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task { @MainActor in
                    AnalyticsManager.shared.trackScreenView(screen, parameters: parameters)
                }
            }
    }
}

extension View {
    func trackScreen(_ screen: AnalyticsScreen, parameters: [String: Any]? = nil) -> some View {
        modifier(ScreenTrackingModifier(screen: screen, parameters: parameters))
    }
}
