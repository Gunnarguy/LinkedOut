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

    var body: some View {
        Group {
            if jobs.visiblePendingJobs.isEmpty {
                emptyState
            } else {
                List(jobs.visiblePendingJobs) { job in
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
                Menu {
                    ForEach(JobSortMode.allCases) { mode in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                jobs.sortMode = mode
                            }
                        } label: {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Label(jobs.sortMode.rawValue, systemImage: jobs.sortMode.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(jobs.sortMode.tint)
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
