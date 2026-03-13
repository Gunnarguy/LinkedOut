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

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            // Run discovery once at launch
            if let found = await ServerDiscovery.discover() {
                serverURL = found
            }
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
