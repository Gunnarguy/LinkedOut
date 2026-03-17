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
    /// True when cached profile exists but backend session is invalid — LinkedIn API calls will fail
    @Published var needsReauth = false

    /// Controls the OAuth WKWebView sheet
    @Published var showOAuth = false
    @Published var oauthURL: URL?

    /// Stored person ID for session persistence
    @AppStorage("personId") private var storedPersonId: String = ""

    /// Cached profile JSON so we can show profile immediately without backend
    @AppStorage("cachedProfileJSON") private var cachedProfileJSON: String = ""

    init() {
        // Restore cached profile immediately (no network needed)
        if let cached = loadCachedProfile() {
            self.profile = cached
            self.isAuthenticated = true
        }
        // Then verify with backend in background
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
                self.needsReauth = false
                cacheProfile(profile)
            } else {
                // Backend says not authenticated — keep cached profile for display
                // but flag that LinkedIn API calls will fail until re-auth
                if loadCachedProfile() != nil {
                    self.isAuthenticated = true
                    self.needsReauth = true
                } else {
                    clearSession()
                }
            }
        } catch {
            // Backend not reachable — keep cached session, don't flag re-auth
            // (could just be temporary network issue)
            if loadCachedProfile() != nil {
                self.isAuthenticated = true
            }
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
                self.needsReauth = false
                cacheProfile(profile)
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

    /// Pull fresh full resume data from LinkedIn API via backend
    func fetchResume() async {
        guard !storedPersonId.isEmpty, storedPersonId != "dev-user" else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let profile = try await APIClient.shared.fetchResume(personId: storedPersonId)
            self.profile = profile
            cacheProfile(profile)
        } catch {
            self.error = "Failed to fetch resume: \(error.localizedDescription)"
        }
    }

    func signOut() {
        clearSession()
    }

    private func clearSession() {
        isAuthenticated = false
        needsReauth = false
        profile = nil
        storedPersonId = ""
        cachedProfileJSON = ""
    }

    // MARK: - Profile caching helpers

    private func cacheProfile(_ profile: LinkedInProfile) {
        if let data = try? JSONEncoder().encode(profile),
           let json = String(data: data, encoding: .utf8) {
            cachedProfileJSON = json
        }
    }

    private func loadCachedProfile() -> LinkedInProfile? {
        guard !cachedProfileJSON.isEmpty,
              let data = cachedProfileJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LinkedInProfile.self, from: data)
    }
}
