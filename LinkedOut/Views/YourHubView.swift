//
//  YourHubView.swift
//  LinkedOut
//
//  Unified "You" hub — profile, pipeline stats, preferences, and account
//  all in one creative, scrollable dashboard.
//

import SwiftUI

struct YourHubView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var jobs: JobsViewModel

    @State private var showSettings = false
    @State private var navigateTo: PipelineDestination?

    enum PipelineDestination: Hashable {
        case pending, applied, saved, rejected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileHero
                    pipelineDashboard
                    quickActions
                    accountSection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await jobs.loadStats() }
            .task { await jobs.loadStats() }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $navigateTo) { dest in
                switch dest {
                case .pending:
                    PendingJobsListView()
                case .applied:
                    EmbeddedAppliedJobsView()
                case .saved:
                    EmbeddedSavedJobsView()
                case .rejected:
                    RejectedJobsView()
                }
            }
        }
    }

    // MARK: - Profile Hero Card

    private var profileHero: some View {
        VStack(spacing: 16) {
            // Avatar
            if let profile = auth.profile {
                if let picUrl = URL(string: profile.profilePictureUrl),
                   !profile.profilePictureUrl.isEmpty {
                    AsyncImage(url: picUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        default:
                            heroInitials(profile)
                        }
                    }
                } else {
                    heroInitials(profile)
                }

                Text(profile.fullName)
                    .font(.title2.bold())

                if !profile.headline.isEmpty {
                    Text(profile.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if !profile.email.isEmpty {
                    Label(profile.email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !profile.vanityName.isEmpty, let url = URL(string: profile.profileUrl) {
                    Link(destination: url) {
                        Label("LinkedIn Profile", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.medium))
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Profile Loaded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Pipeline Dashboard

    private var pipelineDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pipeline", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            if let stats = jobs.stats {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    Button { navigateTo = .pending } label: {
                        StatCard(
                            label: "In Queue",
                            value: stats.pending,
                            icon: "tray.full.fill",
                            gradient: Gradient(colors: [.orange, .yellow])
                        )
                    }
                    .buttonStyle(.plain)

                    Button { navigateTo = .applied } label: {
                        StatCard(
                            label: "Applied",
                            value: stats.applied,
                            icon: "checkmark.seal.fill",
                            gradient: Gradient(colors: [.green, .mint])
                        )
                    }
                    .buttonStyle(.plain)

                    Button { navigateTo = .saved } label: {
                        StatCard(
                            label: "Saved",
                            value: stats.saved,
                            icon: "bookmark.fill",
                            gradient: Gradient(colors: [.blue, .cyan])
                        )
                    }
                    .buttonStyle(.plain)

                    Button { navigateTo = .rejected } label: {
                        StatCard(
                            label: "Passed",
                            value: stats.rejected,
                            icon: "hand.wave.fill",
                            gradient: Gradient(colors: [.red, .pink])
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else if jobs.statsLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
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
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 12) {
            // Preferences — the main settings CTA
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.indigo.gradient)
                            .frame(width: 40, height: 40)
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.bold())
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Job Preferences")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Roles, salary, strictness, scoring weights")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(spacing: 12) {
            Label("Account", systemImage: "person.badge.shield.checkmark")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                if auth.profile?.personId == "dev-user" {
                    Button {
                        Task { await auth.signInWithLinkedIn() }
                    } label: {
                        HStack {
                            Image(systemName: "link.badge.plus")
                                .foregroundStyle(.blue)
                            Text("Connect LinkedIn")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isLoading)

                    Divider().padding(.leading, 44)
                }

                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                        Text("Sign Out")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Helpers

    private func heroInitials(_ profile: LinkedInProfile) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
                .shadow(color: .blue.opacity(0.25), radius: 8, y: 4)
            Text("\(profile.firstName.prefix(1))\(profile.lastName.prefix(1))")
                .font(.title.bold())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Embedded Job Lists (no NavigationStack — pushed inside YourHubView)

private struct EmbeddedAppliedJobsView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @State private var selectedJob: JobPayload?

    var body: some View {
        Group {
            if jobs.appliedJobs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No applications yet")
                        .font(.headline)
                    Text("Swipe right on jobs to apply")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List(jobs.appliedJobs) { job in
                    Button { selectedJob = job } label: {
                        JobListRow(job: job, showStatus: true)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Applied")
        .task { await jobs.loadAppliedJobs() }
        .refreshable { await jobs.loadAppliedJobs() }
        .sheet(item: $selectedJob) { job in
            JobDetailView(job: job)
        }
    }
}

private struct EmbeddedSavedJobsView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @State private var selectedJob: JobPayload?

    var body: some View {
        Group {
            if jobs.savedJobs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No saved jobs")
                        .font(.headline)
                    Text("Swipe up on jobs to save for later")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List(jobs.savedJobs) { job in
                    Button { selectedJob = job } label: {
                        JobListRow(job: job, showStatus: true)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Saved")
        .task { await jobs.loadSavedJobs() }
        .refreshable { await jobs.loadSavedJobs() }
        .sheet(item: $selectedJob) { job in
            JobDetailView(job: job)
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: Int
    let icon: String
    let gradient: Gradient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            gradient: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text("\(value)")
                .font(.system(.title, design: .rounded).bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}
