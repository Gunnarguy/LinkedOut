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
            print("[AUTH] ♻️ Restored cached profile: \(cached.firstName) \(cached.lastName) (\(cached.personId))")
        } else {
            print("[AUTH] 🆕 No cached profile found")
        }
        // NOTE: Do NOT call checkExistingSession() here — MainTabView calls it
        // after ServerDiscovery.discover() so we verify against the right backend.
        if !storedPersonId.isEmpty {
            print("[AUTH] 🔍 Stored personId='\(storedPersonId)' — will verify after server discovery")
        } else {
            print("[AUTH] ⚠️ No stored personId — user needs to sign in")
        }
    }

    func checkExistingSession() async {
        guard !storedPersonId.isEmpty else {
            print("[AUTH] ⏭️ checkExistingSession skipped — no stored personId")
            return
        }
        print("[AUTH] 🔄 Checking session for personId='\(storedPersonId)'...")
        isLoading = true
        defer { isLoading = false }

        do {
            let status = try await APIClient.shared.checkAuthStatus(personId: storedPersonId)
            print("[AUTH] 📡 Backend auth status: authenticated=\(status.authenticated), hasProfile=\(status.profile != nil)")
            if status.authenticated, let profile = status.profile {
                self.profile = profile
                self.isAuthenticated = true
                self.needsReauth = false
                cacheProfile(profile)
                print("[AUTH] ✅ Session valid — \(profile.firstName) \(profile.lastName)")
            } else {
                // Backend says not authenticated — keep cached profile for display
                // but flag that LinkedIn API calls will fail until re-auth
                if loadCachedProfile() != nil {
                    self.isAuthenticated = true
                    self.needsReauth = true
                    print("[AUTH] ⚠️ Backend says NOT authenticated — using cached profile, needsReauth=true")
                } else {
                    print("[AUTH] 🚫 Backend says NOT authenticated and NO cached profile — clearing session")
                    clearSession()
                }
            }
        } catch {
            // Backend not reachable — keep cached session, don't flag re-auth
            // (could just be temporary network issue)
            print("[AUTH] ❌ Backend unreachable: \(error.localizedDescription)")
            if loadCachedProfile() != nil {
                self.isAuthenticated = true
                print("[AUTH] 🔒 Keeping cached profile (backend may be temporarily down)")
            }
        }
    }

    func signInWithLinkedIn() async {
        print("[AUTH] 🔑 signInWithLinkedIn() called — fetching auth URL from backend...")
        isLoading = true
        error = nil

        do {
            let loginInfo = try await APIClient.shared.fetchLoginURL()
            print("[AUTH] 📎 Got authorization URL: \(loginInfo.authorizationUrl.prefix(80))...")
            guard let url = URL(string: loginInfo.authorizationUrl) else {
                print("[AUTH] ❌ Invalid authorization URL string!")
                error = "Invalid authorization URL"
                isLoading = false
                return
            }
            oauthURL = url
            showOAuth = true
            print("[AUTH] 🪟 showOAuth=true — OAuth sheet should now appear")
            isLoading = false
        } catch {
            print("[AUTH] ❌ Failed to fetch login URL: \(error.localizedDescription)")
            self.error = "Failed to start sign-in: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Called by OAuthWebView when it intercepts the redirect with code + state.
    func handleOAuthCallback(code: String, state: String) async {
        print("[AUTH] 🔄 handleOAuthCallback — code=\(code.prefix(10))..., state=\(state.prefix(10))...")
        isLoading = true
        error = nil

        do {
            print("[AUTH] 📡 Exchanging code for token via POST /auth/token...")
            let status = try await APIClient.shared.exchangeToken(code: code, state: state)
            print("[AUTH] 📡 Token exchange response: authenticated=\(status.authenticated), hasProfile=\(status.profile != nil)")
            if status.authenticated, let profile = status.profile {
                self.profile = profile
                self.storedPersonId = profile.personId
                self.isAuthenticated = true
                self.needsReauth = false
                cacheProfile(profile)
                print("[AUTH] ✅ OAuth complete! Signed in as \(profile.firstName) \(profile.lastName) (personId=\(profile.personId))")
            } else {
                print("[AUTH] ❌ Token exchange succeeded but backend didn't authenticate")
                self.error = "Authentication failed — backend didn't create a session"
            }
        } catch {
            print("[AUTH] ❌ Token exchange failed: \(error.localizedDescription)")
            self.error = "Sign-in failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func cancelOAuth() {
        print("[AUTH] 🚪 OAuth cancelled by user")
        showOAuth = false
        oauthURL = nil
        isLoading = false
    }

    /// Skip sign-in for dev mode — use mock data
    func continueWithoutSignIn() {
        print("[AUTH] 🛠️ Dev mode — continuing without sign-in")
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
        guard !storedPersonId.isEmpty, storedPersonId != "dev-user" else {
            print("[AUTH] ⏭️ fetchResume skipped — no valid personId")
            return
        }
        guard !needsReauth else {
            print("[AUTH] 🚫 fetchResume blocked — needsReauth=true (session expired)")
            self.error = "LinkedIn session expired — tap Reconnect in the You tab"
            return
        }
        print("[AUTH] 📄 Fetching resume for personId='\(storedPersonId)'...")
        isLoading = true
        defer { isLoading = false }

        do {
            let profile = try await APIClient.shared.fetchResume(personId: storedPersonId)
            self.profile = profile
            cacheProfile(profile)
            print("[AUTH] ✅ Resume fetched — \(profile.firstName) \(profile.lastName)")
        } catch {
            print("[AUTH] ❌ Resume fetch failed: \(error.localizedDescription)")
            self.error = "Failed to fetch resume: \(error.localizedDescription)"
        }
    }

    func signOut() {
        print("[AUTH] 👋 Sign out requested")
        clearSession()
    }

    private func clearSession() {
        print("[AUTH] 🧹 Clearing session — isAuthenticated=false, needsReauth=false, personId cleared")
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
