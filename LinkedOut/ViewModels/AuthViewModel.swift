//
//  AuthViewModel.swift
//  LinkedOut
//
//  Manages authentication state.
//

import Combine
import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var profile: LinkedInProfile?
    @Published var isLoading = false
    @Published var error: String?

    /// Controls the OAuth WKWebView sheet
    @Published var showOAuth = false
    @Published var oauthURL: URL?

    /// Stored person ID for session persistence
    @AppStorage("personId") private var storedPersonId: String = ""

    init() {
        // Check for existing session on launch
        if !storedPersonId.isEmpty {
            Task { await checkExistingSession() }
        }
    }

    func checkExistingSession() async {
        guard !storedPersonId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let status = try await APIClient.shared.checkAuthStatus(personId: storedPersonId)
            if status.authenticated, let profile = status.profile {
                self.profile = profile
                self.isAuthenticated = true
            } else {
                clearSession()
            }
        } catch {
            // Backend not reachable — keep stored session optimistically
            self.isAuthenticated = !storedPersonId.isEmpty
        }
    }

    func signInWithLinkedIn() async {
        isLoading = true
        error = nil

        do {
            let loginInfo = try await APIClient.shared.fetchLoginURL()
            guard let url = URL(string: loginInfo.authorizationUrl) else {
                error = "Invalid authorization URL"
                isLoading = false
                return
            }
            oauthURL = url
            showOAuth = true
            isLoading = false
        } catch {
            self.error = "Failed to start sign-in: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Called by OAuthWebView when it intercepts the redirect with code + state.
    func handleOAuthCallback(code: String, state: String) async {
        isLoading = true
        error = nil

        do {
            let status = try await APIClient.shared.exchangeToken(code: code, state: state)
            if status.authenticated, let profile = status.profile {
                self.profile = profile
                self.storedPersonId = profile.personId
                self.isAuthenticated = true
            } else {
                self.error = "Authentication failed — backend didn't create a session"
            }
        } catch {
            self.error = "Sign-in failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func cancelOAuth() {
        showOAuth = false
        oauthURL = nil
        isLoading = false
    }

    /// Skip sign-in for dev mode — use mock data
    func continueWithoutSignIn() {
        self.isAuthenticated = true
        self.profile = LinkedInProfile(
            personId: "dev-user",
            firstName: "Dev",
            lastName: "Mode",
            headline: "Building cool stuff",
            vanityName: "devmode",
            profilePictureUrl: "",
            email: "dev@linkedout.app"
        )
        self.storedPersonId = "dev-user"
    }

    func signOut() {
        clearSession()
    }

    private func clearSession() {
        isAuthenticated = false
        profile = nil
        storedPersonId = ""
    }
}
