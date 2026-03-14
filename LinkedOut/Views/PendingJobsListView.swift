//
//  PendingJobsListView.swift
//  LinkedOut
//
//  List view of jobs in the pending queue (navigated from Pipeline dashboard).
//

import SwiftUI

struct PendingJobsListView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @State private var selectedJob: JobPayload?
    @State private var sortByNewest = false

    private var sortedPending: [JobPayload] {
        if sortByNewest {
            return jobs.pendingJobs.sorted {
                ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast)
            }
        }
        return jobs.pendingJobs // default: sorted by score
    }

    var body: some View {
        Group {
            if jobs.pendingJobs.isEmpty {
                emptyState
            } else {
                List(sortedPending) { job in
                    Button {
                        selectedJob = job
                    } label: {
                        JobListRow(job: job, showStatus: false)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("In Queue")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        sortByNewest.toggle()
                    }
                } label: {
                    Image(systemName: sortByNewest ? "clock.fill" : "tray.full.fill")
                        .foregroundStyle(sortByNewest ? .orange : .blue)
                }
            }
        }
        .task { await jobs.loadPendingJobs() }
        .refreshable { await jobs.loadPendingJobs() }
        .sheet(item: $selectedJob) { job in
            JobDetailView(job: job)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Queue is empty")
                .font(.headline)
            Text("Run an ingest to find new jobs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
