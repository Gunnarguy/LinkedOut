//
//  CardStackView.swift
//  LinkedOut
//
//  Tinder-style swipeable card stack — the main interaction.
//

import SwiftUI
import UIKit

struct CardStackView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @State private var sortByNewest = false
    @State private var showListView = false

    /// Sorted view of pending jobs — either by score (default) or newest first
    private var sortedPending: [JobPayload] {
        if sortByNewest {
            return jobs.pendingJobs.sorted {
                ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast)
            }
        }
        return jobs.pendingJobs // already sorted by score from backend
    }

    var body: some View {
        NavigationStack {
            Group {
                if jobs.isLoading && jobs.pendingJobs.isEmpty {
                    loadingView
                } else if jobs.pendingJobs.isEmpty {
                    emptyView
                } else if showListView {
                    pendingListView
                } else {
                    cardStack
                }
            }
            .navigationTitle("LinkedOut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        // List / Card toggle
                        Button {
                            haptic()
                            withAnimation(.spring(response: 0.3)) {
                                showListView.toggle()
                            }
                        } label: {
                            Image(systemName: showListView ? "rectangle.stack.fill" : "list.bullet")
                                .foregroundStyle(showListView ? .orange : .primary)
                        }

                        Button {
                            haptic()
                            Task { await jobs.ingestNewJobs() }
                        } label: {
                            if jobs.isIngesting {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkle.magnifyingglass")
                            }
                        }
                        .disabled(jobs.isIngesting)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Sort toggle
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                sortByNewest.toggle()
                            }
                        } label: {
                            Image(systemName: sortByNewest ? "clock.fill" : "star.fill")
                                .foregroundStyle(sortByNewest ? .orange : .blue)
                        }

                        if let stats = jobs.stats {
                            HStack(spacing: 12) {
                                Label("\(stats.pending)", systemImage: "tray")
                                Label("\(stats.applied)", systemImage: "checkmark.circle")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .task {
                jobs.loadCachedJobs()   // instant — show cached cards while network loads
                await jobs.loadPendingJobs()
                await jobs.autoIngestIfNeeded()
            }
            .task { await jobs.loadStats() }
            .refreshable { await jobs.refreshAll() }
            .sheet(item: $jobs.selectedJob) { job in
                JobDetailView(job: job)
            }
            .alert("Apply to this role?", isPresented: applyAlertBinding) {
                if let job = jobs.jobToApply {
                    let applyURL = (job.applyUrl ?? job.sourceUrl)
                    if let url = URL(string: applyURL) {
                        Button("Open Application") {
                            UIApplication.shared.open(url)
                            Task { await jobs.confirmApply(job: job) }
                        }
                    }
                    Button("Mark Applied (already applied)") {
                        Task { await jobs.confirmApply(job: job) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                if let job = jobs.jobToApply {
                    Text("\(job.roleTitle) at \(job.companyName)")
                }
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

    private var applyAlertBinding: Binding<Bool> {
        Binding(
            get: { jobs.jobToApply != nil },
            set: { if !$0 { jobs.jobToApply = nil } }
        )
    }

    // MARK: - List View

    private var pendingListView: some View {
        List {
            Section {
                ForEach(sortedPending) { job in
                    Button {
                        jobs.selectedJob = job
                    } label: {
                        JobListRow(job: job)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .swipeActions(edge: .trailing) {
                        Button {
                            haptic()
                            Task { await jobs.swipeRight(job: job) }
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                        }
                        .tint(.green)

                        Button {
                            haptic()
                            Task { await jobs.swipeUp(job: job) }
                        } label: {
                            Label("Save", systemImage: "bookmark")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button(role: .destructive) {
                            haptic()
                            Task { await jobs.swipeLeft(job: job) }
                        } label: {
                            Label("Pass", systemImage: "xmark")
                        }
                    }
                }
            } header: {
                Text("\(sortedPending.count) jobs in queue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        VStack(spacing: 0) {
            ZStack {
                // Show up to 3 cards stacked
                ForEach(Array(sortedPending.prefix(3).enumerated().reversed()), id: \.element.id) { index, job in
                    let isTop = index == 0

                    JobCardView(job: job, isTopCard: isTop) {
                        jobs.selectedJob = job
                    }
                    .padding(.horizontal, 16)
                    .offset(
                        x: isTop ? jobs.topCardOffset.width : 0,
                        y: isTop ? jobs.topCardOffset.height : CGFloat(index) * 8
                    )
                    .rotationEffect(
                        isTop ? .degrees(jobs.topCardRotation) : .zero
                    )
                    .scaleEffect(isTop ? 1.0 : 1.0 - CGFloat(index) * 0.04)
                    .zIndex(Double(sortedPending.count - index))
                    .gesture(isTop ? swipeGesture : nil)
                    .allowsHitTesting(isTop)
                }

                // Swipe hint overlay
                if jobs.swipeHint != .none {
                    SwipeHintOverlay(hint: jobs.swipeHint)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 8)

            // Action buttons below cards
            actionButtons
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                jobs.topCardOffset = value.translation
                jobs.topCardRotation = Double(value.translation.width / 20)
            }
            .onEnded { value in
                guard let topJob = sortedPending.first else { return }
                let width = value.translation.width
                let height = value.translation.height

                if width > 120 {
                    // Swipe right → Apply
                    withAnimation(.easeOut(duration: 0.3)) {
                        jobs.topCardOffset = CGSize(width: 600, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        jobs.topCardOffset = .zero
                        jobs.topCardRotation = 0
                        Task { await jobs.swipeRight(job: topJob) }
                    }
                } else if width < -120 {
                    // Swipe left → Reject
                    withAnimation(.easeOut(duration: 0.3)) {
                        jobs.topCardOffset = CGSize(width: -600, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        jobs.topCardOffset = .zero
                        jobs.topCardRotation = 0
                        Task { await jobs.swipeLeft(job: topJob) }
                    }
                } else if height < -120 {
                    // Swipe up → Save
                    withAnimation(.easeOut(duration: 0.3)) {
                        jobs.topCardOffset = CGSize(width: 0, height: -600)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        jobs.topCardOffset = .zero
                        jobs.topCardRotation = 0
                        Task { await jobs.swipeUp(job: topJob) }
                    }
                } else {
                    jobs.resetCardPosition()
                }
            }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 24) {
            // Undo
            Button {
                haptic()
                Task { await jobs.undoLastAction() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 40, height: 40)
                    .background(.orange.opacity(0.1))
                    .clipShape(Circle())
            }

            // Reject
            Button {
                haptic()
                if let job = sortedPending.first {
                    Task { await jobs.swipeLeft(job: job) }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.red)
                    .frame(width: 56, height: 56)
                    .background(.red.opacity(0.1))
                    .clipShape(Circle())
            }
            .disabled(jobs.isProcessingAction)

            // Save
            Button {
                haptic()
                if let job = sortedPending.first {
                    Task { await jobs.swipeUp(job: job) }
                }
            } label: {
                Image(systemName: "bookmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(.blue.opacity(0.1))
                    .clipShape(Circle())
            }
            .disabled(jobs.isProcessingAction)

            // Apply
            Button {
                haptic()
                if let job = sortedPending.first {
                    Task { await jobs.swipeRight(job: job) }
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.green)
                    .frame(width: 56, height: 56)
                    .background(.green.opacity(0.1))
                    .clipShape(Circle())
            }
            .disabled(jobs.isProcessingAction)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Empty & Loading

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No jobs in queue")
                .font(.title3.weight(.medium))
            Text("Tap below to scan job boards\nand run them through the AI filter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if jobs.isIngesting {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(jobs.ingestProgress.isEmpty ? "Scanning & scoring..." : jobs.ingestProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            } else {
                Button {
                    haptic()
                    Task { await jobs.ingestNewJobs() }
                } label: {
                    Label("Find New Jobs", systemImage: "sparkle.magnifyingglass")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }

            Button("Refresh Queue") {
                Task { await jobs.loadPendingJobs() }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading your pipeline...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func haptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
