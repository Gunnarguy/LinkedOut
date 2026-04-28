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
    @AppStorage("serverURL") private var serverURL: String = BackendConfig.defaultServerURL
    @State private var lifecycleRefreshTask: Task<Void, Never>?
    @State private var didCompleteInitialLifecycleRefresh = false

    private func syncCurrentPreferencesToActiveServer() async {
        do {
            _ = try await APIClient.shared.syncPreferences(UserPreferences.currentFromUserDefaults())
            print("[MAIN] ✅ Synced current preferences to active backend")
        } catch {
            print("[MAIN] ⚠️ Failed to sync preferences to active backend: \(error.localizedDescription)")
        }
    }

    private func refreshReason(previous: String, found: String, migrated: Bool) -> String? {
        if found != previous {
            return "server changed: \(previous) → \(found)"
        }
        if migrated {
            return "preferences migrated"
        }
        return nil
    }

    private func queueLifecycleRefresh(trigger: String, allowBeforeInitial: Bool = false) {
        if lifecycleRefreshTask != nil {
            print("[MAIN] ⏭️ Skipping lifecycle refresh (\(trigger)) — refresh already running")
            return
        }

        if !allowBeforeInitial && !didCompleteInitialLifecycleRefresh {
            print("[MAIN] ⏭️ Skipping lifecycle refresh (\(trigger)) — initial refresh still pending")
            return
        }

        lifecycleRefreshTask = Task {
            defer {
                lifecycleRefreshTask = nil
                didCompleteInitialLifecycleRefresh = true
            }
            await runLifecycleRefresh(trigger: trigger)
        }
    }

    private func runLifecycleRefresh(trigger: String) async {
        print("[MAIN] 🔄 Lifecycle refresh started (\(trigger))")

        let migrated = UserPreferences.migrateLegacyCareerPrefsIfNeeded()
        if migrated {
            print("[MAIN] 🔁 Migrated stale broad career prefs to portfolio-first defaults")
        }

        let previous = serverURL
        if let found = await ServerDiscovery.discover() {
            serverURL = found
            print("[MAIN] ✅ Server discovered: \(found)")
            await syncCurrentPreferencesToActiveServer()

            if let reason = refreshReason(previous: previous, found: found, migrated: migrated) {
                print("[MAIN] 🔄 Hard refresh triggered (\(reason)) — clearing local cache before reload")
                jobs.resetLocalJobState()
            }

            await auth.checkExistingSession()
            await jobs.refreshAll()
            await jobs.autoIngestIfNeeded()
        } else {
            print("[MAIN] ❌ Server discovery failed — no backend available")
        }

        jobs.startTelemetryLogger()
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
            print("[MAIN] 🔍 Initial server discovery starting...")
            queueLifecycleRefresh(trigger: "initial launch", allowBeforeInitial: true)
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
                queueLifecycleRefresh(trigger: "scene active")
            }
        }
    }
}
