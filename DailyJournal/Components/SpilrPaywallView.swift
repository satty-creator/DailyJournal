//
//  SpilrPaywallView.swift
//  DailyJournal
//
//  Thin wrapper around RevenueCatUI's PaywallView, rendered from whatever
//  Offering is marked Current in the RevenueCat dashboard — the actual
//  pricing/copy/trial terms live there, not here. See REVENUECAT_SETUP.md.
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct SpilrPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RevenueCatUI.PaywallView()
            .onPurchaseCompleted { _ in
                Task { await EntitlementService.shared.refresh() }
                dismiss()
            }
            .onRestoreCompleted { _ in
                Task { await EntitlementService.shared.refresh() }
                dismiss()
            }
    }
}
