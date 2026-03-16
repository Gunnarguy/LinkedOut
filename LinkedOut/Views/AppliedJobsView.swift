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
    var isNew: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Row 1: Score + Title + Salary + NEW badge ──
            HStack(spacing: 14) {
                ScoreRing(score: job.builderScore, size: 48, lineWidth: 4.5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(job.roleTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if isNew {
                            Text("NEW")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(job.companyName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        if let size = job.companySize, !size.isEmpty, size != "Unknown" {
                            Text("\u{00B7}")
                                .foregroundStyle(.quaternary)
                            Text(size)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(job.salaryDisplay)
                        .font(.subheadline.weight(.semibold))

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

            // ── Row 2: Tag pills (remote, location, experience, job type, stage) ──
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if job.isRemote {
                        pillTag("Remote", icon: "wifi", color: .green)
                    }

                    if !job.location.isEmpty && job.location != "Unknown" && !job.isRemote {
                        pillTag(job.location, icon: "mappin", color: .indigo)
                    }

                    if let level = job.experienceLevel, !level.isEmpty {
                        pillTag(level, icon: "chart.bar.fill", color: .orange)
                    }

                    if let jtype = job.jobType, !jtype.isEmpty, jtype != "Unknown" {
                        pillTag(jtype, icon: "briefcase.fill", color: .blue)
                    }

                    if let stage = job.companyStage, !stage.isEmpty, stage != "Unknown" {
                        pillTag(stage, icon: "building.2", color: .teal)
                    }

                    if showStatus, let status = job.applicationStatus, !status.isEmpty, status != "new" {
                        pillTag(job.statusDisplay, icon: statusIcon(status), color: statusColor(status))
                    }
                }
            }

            // ── Row 3: Job description snippet ──
            if let desc = job.description, !desc.isEmpty {
                HStack(spacing: 0) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(desc.replacingOccurrences(of: "&#x2F;", with: "/")
                            .replacingOccurrences(of: "&#x27;", with: "'")
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // ── Row 4: Tech stack ──
            if let stack = job.techStack, !stack.isEmpty {
                HStack(spacing: 0) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(stack.joined(separator: " \u{00B7} "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // ── Row 5: Requirements (first 2) ──
            if let reqs = job.requirements, !reqs.isEmpty {
                HStack(spacing: 0) {
                    Image(systemName: "checklist")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                        .frame(width: 16)
                    Text(reqs.prefix(3).joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.indigo.opacity(0.8))
                        .lineLimit(1)
                }
            }

            // ── Row 6: Fit reasons (green chips) ──
            if let reasons = job.fitReasons, !reasons.isEmpty {
                HStack(spacing: 0) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .frame(width: 16)
                    Text(reasons.prefix(3).joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            // ── Row 7: Red flags / dealbreakers (if any) ──
            if let warnings = job.dealbreakerWarnings, !warnings.isEmpty {
                HStack(spacing: 0) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(width: 16)
                    Text(warnings.joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            } else if let flags = job.redFlags, !flags.isEmpty {
                HStack(spacing: 0) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(width: 16)
                    Text(flags.prefix(2).joined(separator: " \u{00B7} "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            // ── Row 8: AI quick take (first line) ──
            if !job.aiPitchSummary.isEmpty {
                let firstLine = job.pitchBullets.first ?? job.aiPitchSummary
                HStack(spacing: 0) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                        .frame(width: 16)
                    Text(firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "\u{2022}-\u{2013} ")))
                        .font(.caption2)
                        .foregroundStyle(.purple.opacity(0.8))
                        .lineLimit(2)
                        .italic()
                }
            }

            // ── Row 9: Notes (user-added) ──
            if let notes = job.notes, !notes.isEmpty {
                HStack(spacing: 0) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pillTag(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "applied": return "paperplane.fill"
        case "phone_screen": return "phone.fill"
        case "interview": return "person.2.fill"
        case "offer": return "gift.fill"
        case "rejected": return "xmark.circle"
        default: return "circle"
        }
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
