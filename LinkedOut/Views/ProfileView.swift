//
//  ProfileView.swift
//  LinkedOut
//
//  User profile + pipeline stats.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var jobs: JobsViewModel

    var body: some View {
        NavigationStack {
            List {
                // Profile header
                if let profile = auth.profile {
                    Section {
                        VStack(spacing: 12) {
                            // Avatar
                            if let picUrl = URL(string: profile.profilePictureUrl), !profile.profilePictureUrl.isEmpty {
                                AsyncImage(url: picUrl) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(Circle())
                                    default:
                                        initialsAvatar(profile)
                                    }
                                }
                            } else {
                                initialsAvatar(profile)
                            }

                            Text(profile.fullName)
                                .font(.title2.bold())

                            if !profile.headline.isEmpty {
                                Text(profile.headline)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            if !profile.email.isEmpty {
                                Text(profile.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !profile.vanityName.isEmpty, let url = URL(string: profile.profileUrl) {
                                Link(destination: url) {
                                    Label("View LinkedIn Profile", systemImage: "arrow.up.right.square")
                                        .font(.subheadline)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                // Pipeline stats
                Section("Pipeline") {
                    if let stats = jobs.stats {
                        StatRow(label: "In Queue", value: stats.pending, icon: "tray", color: .orange)
                        StatRow(label: "Applied", value: stats.applied, icon: "checkmark.circle", color: .green)
                        StatRow(label: "Saved", value: stats.saved, icon: "bookmark", color: .blue)
                        StatRow(label: "Rejected", value: stats.rejected, icon: "xmark.circle", color: .red)
                    } else if jobs.statsLoading {
                        ProgressView()
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Couldn't load stats")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await jobs.loadStats() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                // Account actions
                Section {
                    if auth.profile?.personId == "dev-user" {
                        Button {
                            Task { await auth.signInWithLinkedIn() }
                        } label: {
                            Label("Connect LinkedIn", systemImage: "link")
                        }
                        .disabled(auth.isLoading)
                    }

                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .task { await jobs.loadStats() }
            .refreshable { await jobs.loadStats() }
        }
    }

    private func initials(_ profile: LinkedInProfile) -> String {
        let f = profile.firstName.prefix(1)
        let l = profile.lastName.prefix(1)
        return "\(f)\(l)"
    }

    private func initialsAvatar(_ profile: LinkedInProfile) -> some View {
        ZStack {
            Circle()
                .fill(.blue.opacity(0.1))
                .frame(width: 80, height: 80)
            Text(initials(profile))
                .font(.title.bold())
                .foregroundStyle(.blue)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)

            Text(label)

            Spacer()

            Text("\(value)")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}
