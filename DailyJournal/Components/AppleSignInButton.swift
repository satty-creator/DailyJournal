//
//  AppleSignInButton.swift
//  DailyJournal
//
//  Uses ASAuthorizationController directly (rather than SwiftUI's
//  SignInWithAppleButton) so we can supply an explicit
//  ASAuthorizationControllerPresentationContextProviding implementation.
//
//  Background: SwiftUI's SignInWithAppleButton resolves its presentation
//  anchor using UIApplication.shared.windows.first, which on iPadOS with
//  Stage Manager or multi-scene support can return nil or the wrong window,
//  causing the authorization sheet to fail silently with
//  ASAuthorizationError.failed. Driving the flow through our own
//  ASAuthorizationController and providing presentationAnchor(for:)
//  ourselves guarantees the correct window is used on every device.
//

import SwiftUI
import AuthenticationServices
import UIKit

// MARK: - SwiftUI wrapper

struct AppleSignInButton: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        // UIViewRepresentable so we keep Apple's official branded button
        // while controlling the authorization flow ourselves.
        _AppleButtonRepresentable(authViewModel: authViewModel)
            .frame(height: 54)
            .cornerRadius(14)
    }
}

// MARK: - UIViewRepresentable bridge

private struct _AppleButtonRepresentable: UIViewRepresentable {
    let authViewModel: AuthViewModel

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .continue,
            authorizationButtonStyle: .black
        )
        button.cornerRadius = 14
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleTap),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(authViewModel: authViewModel) }
}

// MARK: - Coordinator (owns the ASAuthorizationController)

private final class Coordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    let authViewModel: AuthViewModel

    init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    @objc func handleTap() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        authViewModel.prepareAppleRequest(request)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { await authViewModel.handleAppleSignIn(.success(authorization)) }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { await authViewModel.handleAppleSignIn(.failure(error)) }
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    /// Returns the key window of the foreground-active scene — the correct
    /// anchor on iPad with Stage Manager or multi-window support.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        // Prefer the foreground-active scene; fall back to any connected scene.
        let targetScene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first

        if let window = targetScene?.windows.first(where: { $0.isKeyWindow })
            ?? targetScene?.windows.first {
            return window
        }

        // Last-resort: synthesise a window so we never crash with a nil anchor.
        let fallback = UIWindow()
        fallback.makeKeyAndVisible()
        return fallback
    }
}
