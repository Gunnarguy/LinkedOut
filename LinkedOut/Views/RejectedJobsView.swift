//
//  RejectedJobsView.swift
//  LinkedOut
//
//  Shows jobs the user passed on (swiped left).
//

import SwiftUI

struct RejectedJobsView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @State private var selectedJob: JobPayload?
    @State private var sortByNewest = false

    private var sortedRejected: [JobPayload] {
        if sortByNewest {
            return jobs.rejectedJobs.sorted {
                ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast)
            }
        }
        return jobs.rejectedJobs
    }

    var body: some View {
        Group {
            if jobs.rejectedJobs.isEmpty {
                emptyState
            } else {
                List(sortedRejected) { job in
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
        .navigationTitle("Passed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        sortByNewest.toggle()
                    }
                } label: {
                    Image(systemName: sortByNewest ? "clock.fill" : "hand.wave.fill")
                        .foregroundStyle(sortByNewest ? .orange : .red)
                }
            }
        }
        .task { await jobs.loadRejectedJobs() }
        .refreshable { await jobs.loadRejectedJobs() }
        .sheet(item: $selectedJob) { job in
            JobDetailView(job: job)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.wave")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No passed jobs")
                .font(.headline)
            Text("Jobs you swipe left on will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
