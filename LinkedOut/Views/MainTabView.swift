//
//  MainTabView.swift
//  LinkedOut
//
//  Root tab navigation — the main app shell.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var jobs: JobsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("serverURL") private var serverURL: String = "http://Gunnars-Brain-Extension.local:8443"

    private func syncCurrentPreferencesToActiveServer() async {
        do {
            _ = try await APIClient.shared.syncPreferences(UserPreferences.currentFromUserDefaults())
            print("[MAIN] ✅ Synced current preferences to active backend")
        } catch {
            print("[MAIN] ⚠️ Failed to sync preferences to active backend: \(error.localizedDescription)")
        }
    }

    var body: some View {
        TabView {
            CardStackView()
                .tabItem {
                    Label("Discover", systemImage: "rectangle.stack")
                }
                .badge(jobs.newJobCount)

            JobMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            AppliedJobsView()
                .tabItem {
                    Label("Applied", systemImage: "checkmark.circle")
                }
                .badge(jobs.appliedJobs.count)

            SavedJobsView()
                .tabItem {
                    Label("Saved", systemImage: "bookmark")
                }
                .badge(jobs.savedJobs.count)

            YourHubView()
                .tabItem {
                    Label("You", systemImage: "person.crop.circle")
                }
        }
        .task {
            // Run discovery once at launch
            print("[MAIN] 🔍 Initial server discovery starting...")
            let migrated = UserPreferences.migrateLegacyCareerPrefsIfNeeded()
            if migrated {
                print("[MAIN] 🔁 Migrated stale broad career prefs to portfolio-first defaults")
            }
            let previous = serverURL
            if let found = await ServerDiscovery.discover() {
                serverURL = found
                print("[MAIN] ✅ Server discovered: \(found)")
                await syncCurrentPreferencesToActiveServer()
                if migrated || found != previous {
                    print("[MAIN] 🔄 Initial server changed: \(previous) → \(found) — clearing local cache and refreshing")
                    jobs.resetLocalJobState()
                    await jobs.refreshAll()
                }
                // Re-check auth against the discovered server (not the stale cached URL)
                await auth.checkExistingSession()
            } else {
                print("[MAIN] ❌ Server discovery failed — no backend available")
            }
            // Start background telemetry logging to Xcode console
            jobs.startTelemetryLogger()
        }
        .sheet(isPresented: $auth.showOAuth) {
            if let url = auth.oauthURL {
                OAuthWebView(url: url) { code, state in
                    print("[MAIN] 🎯 OAuth sheet returned code+state — exchanging token...")
                    auth.showOAuth = false
                    Task { await auth.handleOAuthCallback(code: code, state: state) }
                } onCancel: {
                    print("[MAIN] 🚪 OAuth sheet cancelled by user")
                    auth.cancelOAuth()
                }
            } else {
                // This shouldn't happen but log it if it does
                Text("OAuth URL not set")
                    .onAppear { print("[MAIN] ⚠️ OAuth sheet opened but oauthURL is nil!") }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            print("[MAIN] 📱 Scene phase: \(phase == .active ? "active" : phase == .inactive ? "inactive" : "background")")
            if phase == .active {
                Task {
                    let migrated = UserPreferences.migrateLegacyCareerPrefsIfNeeded()
                    let previous = serverURL
                    if let found = await ServerDiscovery.discover() {
                        serverURL = found
                        await syncCurrentPreferencesToActiveServer()
                        if migrated || found != previous {
                            print("[DISCOVERY] Server changed: \(previous) → \(found) — reloading jobs + re-checking auth")
                            jobs.resetLocalJobState()
                            await auth.checkExistingSession()
                            await jobs.refreshAll()
                        }
                    }
                }
            }
        }
    }
}
