//
//  MainTabView.swift
//  LinkedOut
//
//  Root tab navigation — the main app shell.
//

import SwiftUI

struct MainTabView: View {
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
            if let found = await ServerDiscovery.discover() {
                serverURL = found
            }
            // Start background telemetry logging to Xcode console
            jobs.startTelemetryLogger()
        }
        .onChange(of: scenePhase) { _, phase in
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
