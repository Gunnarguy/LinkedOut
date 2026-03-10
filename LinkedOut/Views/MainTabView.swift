//
//  MainTabView.swift
//  LinkedOut
//
//  Root tab navigation — the main app shell.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var jobs: JobsViewModel

    var body: some View {
        TabView {
            CardStackView()
                .tabItem {
                    Label("Discover", systemImage: "rectangle.stack")
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
    }
}
