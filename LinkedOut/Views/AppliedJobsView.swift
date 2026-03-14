//
//  AppliedJobsView.swift
//  LinkedOut
//
//  Shows jobs the user swiped right on.
//

import SwiftUI

struct AppliedJobsView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @State private var selectedJob: JobPayload?
    @State private var sortByNewest = false

    private var sortedApplied: [JobPayload] {
        if sortByNewest {
            return jobs.appliedJobs.sorted {
                ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast)
            }
        }
        return jobs.appliedJobs // backend sorts by status pipeline then score
    }

    /// Group applied jobs by their status for section display
    private var groupedApplied: [(String, [JobPayload])] {
        let order = ["interview", "phone_screen", "offer", "applied", "new", "rejected"]
        let grouped = Dictionary(grouping: sortedApplied) { $0.applicationStatus ?? "new" }
        return order.compactMap { key in
            guard let items = grouped[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }

    private func sectionTitle(_ status: String) -> String {
        switch status {
        case "interview": return "Interviewing"
        case "phone_screen": return "Phone Screen"
        case "offer": return "Offers"
        case "applied": return "Applied"
        case "new": return "New"
        case "rejected": return "Rejected"
        default: return status.capitalized
        }
    }

    private func sectionIcon(_ status: String) -> String {
        switch status {
        case "interview": return "person.2.fill"
        case "phone_screen": return "phone.fill"
        case "offer": return "gift.fill"
        case "applied": return "paperplane.fill"
        case "new": return "sparkles"
        case "rejected": return "xmark.circle"
        default: return "circle"
        }
    }

    private func sectionColor(_ status: String) -> Color {
        switch status {
        case "interview": return .purple
        case "phone_screen": return .orange
        case "offer": return .green
        case "applied": return .blue
        case "new": return .secondary
        case "rejected": return .red
        default: return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if jobs.appliedJobs.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedApplied, id: \.0) { status, items in
                            Section {
                                ForEach(items) { job in
                                    Button {
                                        selectedJob = job
                                    } label: {
                                        JobListRow(job: job, showStatus: true)
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: sectionIcon(status))
                                    Text(sectionTitle(status))
                                    Spacer()
                                    Text("\(items.count)")
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(sectionColor(status))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Applied")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            sortByNewest.toggle()
                        }
                    } label: {
                        Image(systemName: sortByNewest ? "clock.fill" : "list.bullet")
                            .foregroundStyle(sortByNewest ? .orange : .blue)
                    }
                }
            }
            .task { await jobs.loadAppliedJobs() }
            .refreshable { await jobs.loadAppliedJobs() }
            .sheet(item: $selectedJob) { job in
                JobDetailView(job: job)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 4) {
                    if let error = jobs.error {
                        ErrorBanner(message: error) {
                            jobs.dismissError()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let info = jobs.info {
                        InfoBanner(message: info) {
                            jobs.dismissInfo()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.3), value: jobs.error)
            .animation(.spring(response: 0.3), value: jobs.info)
        }
    }

    private var emptyState: some View {
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
    }
}

struct SavedJobsView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @State private var selectedJob: JobPayload?
    @State private var sortByNewest = false

    private var sortedSaved: [JobPayload] {
        if sortByNewest {
            return jobs.savedJobs.sorted {
                ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast)
            }
        }
        return jobs.savedJobs // backend sorts by score descending
    }

    var body: some View {
        NavigationStack {
            Group {
                if jobs.savedJobs.isEmpty {
                    emptyState
                } else {
                    List(sortedSaved) { job in
                        Button {
                            selectedJob = job
                        } label: {
                            JobListRow(job: job, showStatus: true)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            sortByNewest.toggle()
                        }
                    } label: {
                        Image(systemName: sortByNewest ? "clock.fill" : "star.fill")
                            .foregroundStyle(sortByNewest ? .orange : .blue)
                    }
                }
            }
            .task { await jobs.loadSavedJobs() }
            .refreshable { await jobs.loadSavedJobs() }
            .sheet(item: $selectedJob) { job in
                JobDetailView(job: job)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 4) {
                    if let error = jobs.error {
                        ErrorBanner(message: error) {
                            jobs.dismissError()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let info = jobs.info {
                        InfoBanner(message: info) {
                            jobs.dismissInfo()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.3), value: jobs.error)
            .animation(.spring(response: 0.3), value: jobs.info)
        }
    }

    private var emptyState: some View {
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
    }
}

// MARK: - Shared Row

struct JobListRow: View {
    let job: JobPayload
    var showStatus: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ScoreRing(score: job.builderScore, size: 44, lineWidth: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.roleTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(job.companyName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(job.salaryDisplay)
                        .font(.subheadline.weight(.medium))

                    if job.isRemote {
                        Text("Remote")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    // Posted date
                    HStack(spacing: 3) {
                        Circle()
                            .fill(rowFreshnessColor(job))
                            .frame(width: 5, height: 5)
                        Text(job.freshnessLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Status badge + notes preview
            HStack(spacing: 8) {
                if showStatus, let status = job.applicationStatus, !status.isEmpty, status != "new" {
                    Text(job.statusDisplay)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.12))
                        .foregroundStyle(statusColor(status))
                        .clipShape(Capsule())
                }

                if let stage = job.companyStage, !stage.isEmpty, stage != "Unknown" {
                    Text(stage)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.teal.opacity(0.1))
                        .foregroundStyle(.teal)
                        .clipShape(Capsule())
                }

                if let stack = job.techStack, !stack.isEmpty {
                    Text(stack.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let notes = job.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "applied": return .blue
        case "phone_screen": return .orange
        case "interview": return .purple
        case "offer": return .green
        case "rejected": return .red
        default: return .secondary
        }
    }

    private func rowFreshnessColor(_ job: JobPayload) -> Color {
        guard let date = job.postedAt else { return .gray }
        let hours = -date.timeIntervalSinceNow / 3600
        if hours < 6 { return .green }
        if hours < 24 { return .blue }
        if hours < 72 { return .orange }
        return .gray
    }
}
