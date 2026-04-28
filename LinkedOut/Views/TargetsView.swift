import SwiftUI

struct TargetsView: View {
    @State private var targets: [PitchTarget] = PitchTargetStore.loadTargets()
    @State private var searchText = ""
    @State private var filter: TargetFilter = .all

    private enum TargetFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case realisticBuyers = "Buyers"
        case partnershipTargets = "Partners"
        case aspirationalComps = "Comps"
        case topPriority = "85+"

        var id: String { rawValue }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredTargets: [PitchTarget] {
        targets.filter(matchesFilters)
    }

    private var visibleTracks: [PitchTrack] {
        switch filter {
        case .all, .topPriority:
            return PitchTrack.allCases.filter { !targets(in: $0).isEmpty }
        case .realisticBuyers:
            return [.realisticBuyer]
        case .partnershipTargets:
            return [.partnershipTarget]
        case .aspirationalComps:
            return [.aspirationalComp]
        }
    }

    private var buyerCount: Int {
        targets.filter { $0.track == .realisticBuyer }.count
    }

    private var partnershipCount: Int {
        targets.filter { $0.track == .partnershipTarget }.count
    }

    private var compCount: Int {
        targets.filter { $0.track == .aspirationalComp }.count
    }

    private var notedCount: Int {
        targets.filter(\.hasNotes).count
    }

    var body: some View {
        List {
            Section {
                overviewCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if filteredTargets.isEmpty {
                ContentUnavailableView(
                    "No Targets Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different filter or broaden the search terms.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(visibleTracks) { track in
                    Section {
                        ForEach(targets(in: track)) { target in
                            NavigationLink {
                                PitchTargetDetailView(targetID: target.id) {
                                    reloadTargets()
                                }
                            } label: {
                                TargetRow(target: target)
                            }
                        }
                    } header: {
                        TrackSectionHeader(track: track, count: targets(in: track).count)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Targets")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search company, thesis, or route")
        .refreshable { reloadTargets() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(TargetFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Startup-scale targets for the OpenIntelligence logic")
                .font(.headline)

            Text("This version is intentionally grounded: founder-led or late-stage private companies only, split into realistic buyers, partnership targets, and aspirational comps. No giant-platform moonshots.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(targets.count) companies total")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatPill(label: "Buyers", value: "\(buyerCount)", tint: trackTint(for: .realisticBuyer))
                StatPill(label: "Partners", value: "\(partnershipCount)", tint: trackTint(for: .partnershipTarget))
                StatPill(label: "Comps", value: "\(compCount)", tint: trackTint(for: .aspirationalComp))
                StatPill(label: "Noted", value: "\(notedCount)", tint: .orange)
            }

            HStack(spacing: 8) {
                FilterChip(label: filter.rawValue == "All" ? "All tracks" : filter.rawValue, tint: .indigo)
                if !query.isEmpty {
                    FilterChip(label: "Search active", tint: .teal)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.16), .blue.opacity(0.08), .teal.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 2)
    }

    private func reloadTargets() {
        targets = PitchTargetStore.loadTargets()
    }

    private func matchesFilters(_ target: PitchTarget) -> Bool {
        let matchesFilter: Bool
        switch filter {
        case .all:
            matchesFilter = true
        case .realisticBuyers:
            matchesFilter = target.track == .realisticBuyer
        case .partnershipTargets:
            matchesFilter = target.track == .partnershipTarget
        case .aspirationalComps:
            matchesFilter = target.track == .aspirationalComp
        case .topPriority:
            matchesFilter = target.isTopPriority
        }

        guard matchesFilter else { return false }
        guard !query.isEmpty else { return true }
        return target.searchableText.contains(query)
    }

    private func targets(in track: PitchTrack) -> [PitchTarget] {
        filteredTargets.filter { $0.track == track }
    }
}

private struct TargetRow: View {
    let target: PitchTarget

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(target.companyName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(target.track.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(trackTint(for: target.track).opacity(0.12), in: Capsule())
                        .foregroundStyle(trackTint(for: target.track))

                    Text(target.market)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Text(target.buyerRationale)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    Label(target.contactTarget, systemImage: target.track.routeIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if target.hasNotes {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 6) {
                ScoreRing(score: target.priorityFraction, size: 48, lineWidth: 5)
                Text(target.priorityLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PitchTargetDetailView: View {
    let targetID: String
    let onSave: () -> Void

    @State private var target: PitchTarget?
    @State private var noteDraft = ""
    @State private var showSavedState = false

    var body: some View {
        Group {
            if let target {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard(target)
                        detailCard(
                            title: target.track == .aspirationalComp ? "Why It Matters" : "Why They'd Buy It",
                            icon: "sparkles.rectangle.stack",
                            tint: .blue,
                            bodyText: target.buyerRationale
                        )
                        detailCard(
                            title: "Strategic Fit",
                            icon: "point.3.connected.trianglepath.dotted",
                            tint: .indigo,
                            bodyText: target.strategicFit
                        )
                        detailCard(
                            title: "Pitch Angle",
                            icon: "megaphone",
                            tint: .teal,
                            bodyText: target.pitchAngle
                        )
                        routeCard(target)
                        notesCard
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                ContentUnavailableView(
                    "Target Missing",
                    systemImage: "building.2.crop.circle",
                    description: Text("This target could not be loaded from local storage.")
                )
            }
        }
        .navigationTitle(target?.companyName ?? "Target")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadTarget)
        .onDisappear { persistNotes(showFeedback: false) }
    }

    private func loadTarget() {
        guard let loaded = PitchTargetStore.target(withID: targetID) else {
            target = nil
            noteDraft = ""
            return
        }

        target = loaded
        noteDraft = loaded.notes
    }

    private func persistNotes(showFeedback: Bool) {
        let existing = PitchTargetStore.note(for: targetID)
        guard existing != noteDraft else { return }

        PitchTargetStore.saveNotes(noteDraft, for: targetID)
        target = PitchTargetStore.target(withID: targetID)
        onSave()

        guard showFeedback else { return }
        withAnimation {
            showSavedState = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation {
                    showSavedState = false
                }
            }
        }
    }

    private func headerCard(_ target: PitchTarget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(target.track.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(trackTint(for: target.track).opacity(0.12), in: Capsule())
                            .foregroundStyle(trackTint(for: target.track))

                        Text(target.market)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)

                        if target.hasNotes {
                            Text("Noted")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(target.companyName)
                        .font(.title2.bold())

                    Text(target.contactTarget)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    ScoreRing(score: target.priorityFraction, size: 84, lineWidth: 8)
                    Text(target.priorityLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let url = URL(string: target.websiteURL) {
                Link(destination: url) {
                    Label("Open company site", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(.indigo)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    private func detailCard(title: String, icon: String, tint: Color, bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func routeCard(_ target: PitchTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(target.track.routeTitle, systemImage: target.track.routeIcon)
                .font(.headline)
                .foregroundStyle(trackTint(for: target.track))

            Text(target.contactTarget)
                .font(.subheadline.weight(.medium))

            Text(target.track.routeGuidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your Notes", systemImage: "note.text")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                if showSavedState {
                    Text("Saved locally")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            ZStack(alignment: .topLeading) {
                if noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Track warm intro ideas, product hooks, or names of the right people to contact.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.leading, 10)
                }

                TextEditor(text: $noteDraft)
                    .frame(minHeight: 140)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                persistNotes(showFeedback: true)
            } label: {
                Label("Save Notes", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TrackSectionHeader: View {
    let track: PitchTrack
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(track.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trackTint(for: track))
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(track.sectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FilterChip: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

private func trackTint(for track: PitchTrack) -> Color {
    switch track {
    case .realisticBuyer:
        return .green
    case .partnershipTarget:
        return .indigo
    case .aspirationalComp:
        return .orange
    }
}
