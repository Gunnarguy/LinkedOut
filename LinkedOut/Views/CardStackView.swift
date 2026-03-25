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
    @State private var showListView = false
    @State private var showFilters = false
    @State private var filters = JobFilters()
    @AppStorage("lastViewedTimestamp") private var lastViewedTimestamp: Double = 0

    // ── Location Filtering ──
    @AppStorage("preferredLocationsJSON") private var preferredLocationsJSON: String = "[\"Kalamazoo, Michigan\"]"
    @State private var selectedLocationTab: String = "All"
    @State private var showLocationManager = false
    @State private var editableLocations: [String] = []

    /// All unique tech stacks across pending jobs (for filter sheet)
    private var availableTechStacks: [String] {
        var counts: [String: Int] = [:]
        for job in jobs.pendingJobs {
            for tech in job.techStack ?? [] {
                counts[tech, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// All unique sources across pending jobs
    private var availableSources: [String] {
        Array(Set(jobs.pendingJobs.map(\.sourceName))).sorted()
    }

    /// Filtered + sorted pending jobs (sort handled by ViewModel)
    private var sortedPending: [JobPayload] {
        var result = jobs.visiblePendingJobs
        if filters.isActive {
            result = result.filter { filters.matches($0) }
        }
        return result
    }

    // ── Location Helpers ──

    private var preferredLocations: [String] {
        guard let data = preferredLocationsJSON.data(using: .utf8),
              let locs = try? JSONDecoder().decode([String].self, from: data) else {
            return ["Kalamazoo, Michigan"]
        }
        return locs
    }

    private var locationTabs: [LocationTab] {
        var tabs: [LocationTab] = [
            LocationTab(id: "All", label: "All", icon: "tray.full", count: sortedPending.count, tint: .primary),
            LocationTab(id: "Remote", label: "Remote", icon: "wifi", count: sortedPending.filter(\.isRemote).count, tint: .green),
        ]
        for loc in preferredLocations {
            let city = loc.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? loc
            let count = sortedPending.filter { jobMatchesCity($0, city: city) }.count
            tabs.append(LocationTab(id: loc, label: city, icon: "mappin", count: count, tint: .blue))
        }
        return tabs
    }

    /// Jobs filtered by the currently selected location tab
    private var locationFilteredJobs: [JobPayload] {
        switch selectedLocationTab {
        case "All":
            return sortedPending
        case "Remote":
            return sortedPending.filter(\.isRemote)
        default:
            let city = selectedLocationTab.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? selectedLocationTab
            return sortedPending.filter { jobMatchesCity($0, city: city) }
        }
    }

    private func jobMatchesCity(_ job: JobPayload, city: String) -> Bool {
        job.location.localizedCaseInsensitiveContains(city)
    }

    private func saveLocationsToAppStorage() {
        if let data = try? JSONEncoder().encode(editableLocations) {
            preferredLocationsJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    /// The cutoff date: jobs added after this are "new"
    private var lastViewedDate: Date {
        lastViewedTimestamp > 0 ? Date(timeIntervalSince1970: lastViewedTimestamp) : .distantPast
    }

    private func isJobNew(_ job: JobPayload) -> Bool {
        guard let posted = job.postedAt else { return false }
        return posted > lastViewedDate
    }

    var body: some View {
        NavigationStack {
            Group {
                if jobs.isLoading && jobs.pendingJobs.isEmpty {
                    loadingView
                } else if jobs.pendingJobs.isEmpty {
                    emptyView
                } else {
                    VStack(spacing: 0) {
                        LocationBarView(
                            tabs: locationTabs,
                            selectedTab: $selectedLocationTab
                        ) {
                            editableLocations = preferredLocations
                            showLocationManager = true
                        }

                        if showListView {
                            pendingListView
                        } else {
                            cardStack
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if jobs.isIngesting && !jobs.pendingJobs.isEmpty {
                    ingestBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4), value: jobs.isIngesting)
            .navigationTitle("LinkedOut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        if jobs.isOffline {
                            Label("Offline", systemImage: "wifi.slash")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

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
                        // Filter toggle
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .foregroundStyle(filters.isActive ? .orange : .primary)
                        }
                        .overlay(alignment: .topTrailing) {
                            if filters.isActive {
                                Text("\(filters.activeCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(Circle().fill(.orange))
                                    .offset(x: 6, y: -6)
                            }
                        }
                        // Sort picker
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
                // Restore lastSeenTimestamp from persisted value
                if lastViewedTimestamp > 0 {
                    jobs.lastSeenTimestamp = Date(timeIntervalSince1970: lastViewedTimestamp)
                }
                await jobs.loadPendingJobs()
                await jobs.autoIngestIfNeeded()
                // Mark current time so next session knows what's "new"
                let now = Date()
                lastViewedTimestamp = now.timeIntervalSince1970
                jobs.lastSeenTimestamp = now
            }
            .task { await jobs.loadStats() }
            .refreshable { await jobs.refreshAll() }
            .sheet(item: $jobs.selectedJob) { job in
                JobDetailView(job: job)
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(
                    filters: $filters,
                    availableTechStacks: availableTechStacks,
                    availableSources: availableSources
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $jobs.jobToApply) { job in
                ApplyReviewSheet(job: job) {
                    jobs.jobToApply = nil
                    Task { await jobs.confirmApply(job: job) }
                } onCancel: {
                    jobs.jobToApply = nil
                }
            }
            .sheet(isPresented: $showLocationManager, onDismiss: saveLocationsToAppStorage) {
                LocationManagerSheet(locations: $editableLocations)
                    .presentationDetents([.medium, .large])
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

    // MARK: - List View

    private var pendingListView: some View {
        List {
            Section {
                ForEach(locationFilteredJobs) { job in
                    Button {
                        jobs.selectedJob = job
                    } label: {
                        JobListRow(job: job, isNew: isJobNew(job))
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
                HStack {
                    Text("\(locationFilteredJobs.count) jobs\(filters.isActive || selectedLocationTab != "All" ? " (filtered)" : "")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if filters.isActive || selectedLocationTab != "All" {
                        Button("Clear") {
                            filters = JobFilters()
                            selectedLocationTab = "All"
                        }
                            .font(.caption2)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        VStack(spacing: 0) {
            ZStack {
                // Show up to 3 cards stacked
                ForEach(Array(locationFilteredJobs.prefix(3).enumerated().reversed()), id: \.element.id) { index, job in
                    let isTop = index == 0

                    JobCardView(
                        job: job,
                        isTopCard: isTop,
                        isNew: isJobNew(job),
                        queuePosition: isTop ? "\(index + 1) of \(locationFilteredJobs.count)" : nil
                    ) {
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
                    .zIndex(Double(locationFilteredJobs.count - index))
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
                guard let topJob = locationFilteredJobs.first else { return }
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
                    .overlay(alignment: .topTrailing) {
                        if jobs.undoCount > 0 {
                            Text("\(jobs.undoCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Circle().fill(.orange))
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .disabled(jobs.undoCount == 0)
            .opacity(jobs.undoCount == 0 ? 0.4 : 1)

            // Reject
            Button {
                haptic()
                if let job = locationFilteredJobs.first {
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
            .disabled(locationFilteredJobs.first.map { jobs.processingJobIds.contains($0.id) } ?? true)

            // Save
            Button {
                haptic()
                if let job = locationFilteredJobs.first {
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
            .disabled(locationFilteredJobs.first.map { jobs.processingJobIds.contains($0.id) } ?? true)

            // Apply
            Button {
                haptic()
                if let job = locationFilteredJobs.first {
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
            .disabled(locationFilteredJobs.first.map { jobs.processingJobIds.contains($0.id) } ?? true)
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

    private var ingestBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(jobs.ingestProgress.isEmpty ? "Scanning & scoring..." : jobs.ingestProgress)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.3))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.85), .purple.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func haptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
