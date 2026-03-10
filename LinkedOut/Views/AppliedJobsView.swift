//
//  AppliedJobsView.swift
//  LinkedOut
//
//  Shows jobs the user swiped right on.
//

import SwiftUI

struct AppliedJobsView: View {
    @EnvironmentObject var jobs: JobsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if jobs.appliedJobs.isEmpty {
                    emptyState
                } else {
                    List(jobs.appliedJobs) { job in
                        Button {
                            jobs.selectedJob = job
                        } label: {
                            JobListRow(job: job)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Applied")
            .task { await jobs.loadAppliedJobs() }
            .refreshable { await jobs.loadAppliedJobs() }
            .sheet(item: $jobs.selectedJob) { job in
                JobDetailView(job: job)
            }
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

    var body: some View {
        NavigationStack {
            Group {
                if jobs.savedJobs.isEmpty {
                    emptyState
                } else {
                    List(jobs.savedJobs) { job in
                        Button {
                            jobs.selectedJob = job
                        } label: {
                            JobListRow(job: job)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved")
            .task { await jobs.loadSavedJobs() }
            .refreshable { await jobs.loadSavedJobs() }
            .sheet(item: $jobs.selectedJob) { job in
                JobDetailView(job: job)
            }
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

    var body: some View {
        HStack(spacing: 14) {
            ScoreRing(score: job.builderScore, size: 44, lineWidth: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.roleTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

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
            }
        }
        .padding(.vertical, 4)
    }
}
