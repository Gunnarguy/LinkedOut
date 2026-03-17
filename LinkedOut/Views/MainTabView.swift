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
            if let found = await ServerDiscovery.discover() {
                serverURL = found
                print("[MAIN] ✅ Server discovered: \(found)")
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
                    let previous = serverURL
                    if let found = await ServerDiscovery.discover() {
                        serverURL = found
                        if found != previous {
                            print("[DISCOVERY] Server changed: \(previous) → \(found) — reloading jobs")
                            await jobs.loadPendingJobs()
                            await jobs.loadStats()
                        }
                    }
                }
            }
        }
    }
}
