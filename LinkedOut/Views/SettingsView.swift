//
//  SettingsView.swift
//  LinkedOut
//
//  Job preferences & scoring intelligence dashboard.
//

import SwiftUI

// MARK: - Presets

/// Each preset fully defines every weight. "Custom" means the user
/// dragged an individual slider, so we stop overwriting values.
private enum StrictnessPreset: String, CaseIterable, Identifiable {
    case relaxed  = "Relaxed"
    case balanced = "Balanced"
    case strict   = "Strict"
    case custom   = "Custom"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .relaxed:  return "🌊"
        case .balanced: return "⚖️"
        case .strict:   return "🎯"
        case .custom:   return "🔧"
        }
    }

    var tagline: String {
        switch self {
        case .relaxed:  return "Cast a wide net — more volume, more variety"
        case .balanced: return "Good mix of quality and quantity"
        case .strict:   return "Only surface near-perfect matches"
        case .custom:   return "You tweaked something — your rules"
        }
    }

    // Maps preset → concrete weight values
    //         cutoff  convinc  boost   nearby  regional reloc   intl    exp     cred    portfolio
    var weights: (cutoff: Double, convincing: Double, boost: Double,
                  nearby: Double, regional: Double,
                  relocation: Double, international: Double,
                  experience: Double, credential: Double, portfolio: Double) {
        switch self {
        case .relaxed:
            return (0.20, -0.10, 0.15, -0.01, -0.03, -0.05, -0.10, -0.05, -0.05, 0.15)
        case .balanced:
            return (0.35, -0.20, 0.10, -0.03, -0.08, -0.15, -0.25, -0.10, -0.15, 0.10)
        case .strict:
            return (0.50, -0.35, 0.05, -0.05, -0.15, -0.25, -0.40, -0.20, -0.25, 0.05)
        case .custom:
            return (0.35, -0.20, 0.10, -0.03, -0.08, -0.15, -0.25, -0.10, -0.15, 0.10)
        }
    }
}

struct SettingsView: View {
    @AppStorage("minSalary") private var minSalary: Int = 90000
    @AppStorage("requireRemote") private var requireRemote: Bool = true
    @AppStorage("locationPreference") private var locationPreference: String = "Remote"
    @AppStorage("serverURL") private var serverURL: String = "http://Gunnars-Brain-Extension.local:8443"
    @AppStorage("preferredRolesJSON") private var preferredRolesJSON: String = "[]"
    @AppStorage("excludedKeywordsJSON") private var excludedKeywordsJSON: String = "[]"
    @AppStorage("preferredLocationsJSON") private var preferredLocationsJSON: String = "[\"Kalamazoo, Michigan\"]"

    // ── Scoring Weights ──
    @AppStorage("scoreCutoff") private var scoreCutoff: Double = 0.35
    @AppStorage("convincingPenalty") private var convincingPenalty: Double = -0.20
    @AppStorage("convincingBoost") private var convincingBoost: Double = 0.10
    @AppStorage("nearbyPenalty") private var nearbyPenalty: Double = -0.03
    @AppStorage("regionalPenalty") private var regionalPenalty: Double = -0.08
    @AppStorage("relocationPenalty") private var relocationPenalty: Double = -0.15
    @AppStorage("internationalPenalty") private var internationalPenalty: Double = -0.25
    @AppStorage("experiencePenalty") private var experiencePenalty: Double = -0.10
    @AppStorage("credentialPenalty") private var credentialPenalty: Double = -0.15
    @AppStorage("portfolioBoost") private var portfolioBoost: Double = 0.10
    @AppStorage("maxSeniorityLevel") private var maxSeniorityLevel: String = "Mid"

    @State private var preferredRoles: [String] = []
    @State private var preferredLocations: [String] = ["Kalamazoo, Michigan"]
    @State private var excludedKeywords: [String] = []
    @State private var newRole = ""
    @State private var newKeyword = ""
    @State private var newLocationCity = ""
    @State private var newLocationState = ""
    @State private var syncStatus: SyncStatus = .idle
    @State private var pendingSyncTask: Task<Void, Never>?
    @State private var showAdvanced = false
    @State private var showSaveToast = false

    // ── Notion Configuration ──
    @AppStorage("notionToken") private var notionToken: String = ""
    @AppStorage("notionDatabaseId") private var notionDatabaseId: String = "28649a74d54f81d59822e8150b4c830a"
    @State private var notionConnecting = false
    @State private var notionConnected = false
    @State private var notionError: String?
    @State private var notionPropertyCount: Int = 0

    private enum SyncStatus { case idle, syncing, synced, failed(String) }

    // Detect which preset matches current weights (or .custom if none do)
    private var activePreset: StrictnessPreset {
        for preset in [StrictnessPreset.relaxed, .balanced, .strict] {
            let w = preset.weights
            if abs(scoreCutoff - w.cutoff) < 0.01 &&
               abs(convincingPenalty - w.convincing) < 0.01 &&
               abs(convincingBoost - w.boost) < 0.01 &&
               abs(nearbyPenalty - w.nearby) < 0.01 &&
               abs(regionalPenalty - w.regional) < 0.01 &&
               abs(relocationPenalty - w.relocation) < 0.01 &&
               abs(internationalPenalty - w.international) < 0.01 &&
               abs(experiencePenalty - w.experience) < 0.01 &&
               abs(credentialPenalty - w.credential) < 0.01 &&
               abs(portfolioBoost - w.portfolio) < 0.01 {
                return preset
            }
        }
        return .custom
    }

    private var currentPreferences: UserPreferences {
        UserPreferences(
            minSalary: minSalary,
            requireRemote: requireRemote,
            preferredRoles: preferredRoles,
            excludedKeywords: excludedKeywords,
            locationPreference: locationPreference,
            preferredLocations: preferredLocations,
            scoreCutoff: scoreCutoff,
            convincingPenalty: convincingPenalty,
            convincingBoost: convincingBoost,
            nearbyPenalty: nearbyPenalty,
            regionalPenalty: regionalPenalty,
            relocationPenalty: relocationPenalty,
            internationalPenalty: internationalPenalty,
            experiencePenalty: experiencePenalty,
            credentialPenalty: credentialPenalty,
            portfolioBoost: portfolioBoost,
            maxSeniorityLevel: maxSeniorityLevel
        )
    }

    // ── Apply a preset ──
    private func apply(_ preset: StrictnessPreset) {
        guard preset != .custom else { return }
        let w = preset.weights
        withAnimation(.easeInOut(duration: 0.25)) {
            scoreCutoff = w.cutoff
            convincingPenalty = w.convincing
            convincingBoost = w.boost
            nearbyPenalty = w.nearby
            regionalPenalty = w.regional
            relocationPenalty = w.relocation
            internationalPenalty = w.international
            experiencePenalty = w.experience
            credentialPenalty = w.credential
            portfolioBoost = w.portfolio
        }
        debouncedSync()
    }

    var body: some View {
        NavigationStack {
            List {
                // ── How Picky Are You? ──────────────────────────────
                Section {
                    VStack(spacing: 12) {
                        // Preset pills
                        HStack(spacing: 10) {
                            ForEach([StrictnessPreset.relaxed, .balanced, .strict], id: \.self) { preset in
                                PresetPill(
                                    preset: preset,
                                    isActive: activePreset == preset,
                                    onTap: { apply(preset) }
                                )
                            }
                        }

                        // Active description
                        HStack(spacing: 8) {
                            Text(activePreset.emoji)
                                .font(.title2)
                            Text(activePreset.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("How Picky?")
                } footer: {
                    if activePreset == .custom {
                        Text("You tweaked individual weights. Tap a preset to reset them.")
                    } else {
                        Text("Pick a vibe, or open Advanced to fine-tune individual weights.")
                    }
                }

                // ── Live Preview ────────────────────────────────────
                Section {
                    ScoreSimulatorView(
                        convincingPenalty: convincingPenalty,
                        convincingBoost: convincingBoost,
                        nearbyPenalty: nearbyPenalty,
                        regionalPenalty: regionalPenalty,
                        relocationPenalty: relocationPenalty,
                        internationalPenalty: internationalPenalty,
                        experiencePenalty: experiencePenalty,
                        credentialPenalty: credentialPenalty,
                        portfolioBoost: portfolioBoost,
                        scoreCutoff: scoreCutoff
                    )
                } header: {
                    Text("What That Looks Like")
                } footer: {
                    Text("How example jobs score with your current settings.")
                }

                // ── Seniority + Salary + Location (the obvious stuff) ─
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Seniority Level")
                            .font(.subheadline.weight(.semibold))
                        Picker("", selection: $maxSeniorityLevel) {
                            Text("Junior").tag("Junior")
                            Text("Mid").tag("Mid")
                            Text("Senior").tag("Senior")
                            Text("Any").tag("Any")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: maxSeniorityLevel) { _, _ in debouncedSync() }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Minimum Salary")
                                .font(.subheadline)
                            Spacer()
                            Text(formattedSalary)
                                .font(.headline.monospaced())
                        }
                        Slider(
                            value: Binding(
                                get: { Double(minSalary) },
                                set: { minSalary = Int($0) }
                            ),
                            in: 0...300_000,
                            step: 5_000
                        )
                        .onChange(of: minSalary) { _, _ in debouncedSync() }
                    }

                    Toggle("Remote Only", isOn: $requireRemote)
                        .onChange(of: requireRemote) { _, _ in debouncedSync() }
                } header: {
                    Text("The Basics")
                }

                // ── Acceptable Locations ────────────────────────────
                Section {
                    ForEach(preferredLocations, id: \.self) { location in
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.blue)
                            Text(location)
                        }
                    }
                    .onDelete { indexSet in
                        preferredLocations.remove(atOffsets: indexSet)
                        saveLocationsToStorage()
                        debouncedSync()
                    }

                    HStack(spacing: 6) {
                        TextField("City", text: $newLocationCity)
                        Text(",").foregroundStyle(.secondary)
                        TextField("State", text: $newLocationState)
                            .frame(width: 100)
                        Button {
                            let city = newLocationCity.trimmingCharacters(in: .whitespaces)
                            let state = newLocationState.trimmingCharacters(in: .whitespaces)
                            guard !city.isEmpty || !state.isEmpty else { return }
                            let entry = state.isEmpty ? city : "\(city), \(state)"
                            preferredLocations.append(entry)
                            newLocationCity = ""
                            newLocationState = ""
                            saveLocationsToStorage()
                            debouncedSync()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newLocationCity.trimmingCharacters(in: .whitespaces).isEmpty
                                  && newLocationState.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Acceptable Locations")
                } footer: {
                    Text("Cities and states you'd be willing to work in. Jobs in these areas won't be penalized for distance.")
                }

                // ── Roles & Keywords ────────────────────────────────
                Section {
                    ForEach(preferredRoles, id: \.self) { role in
                        Text(role)
                    }
                    .onDelete { indexSet in
                        preferredRoles.remove(atOffsets: indexSet)
                        saveRolesToStorage()
                        debouncedSync()
                    }

                    HStack {
                        TextField("Add role...", text: $newRole)
                        Button {
                            guard !newRole.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            preferredRoles.append(newRole.trimmingCharacters(in: .whitespaces))
                            newRole = ""
                            saveRolesToStorage()
                            debouncedSync()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newRole.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Preferred Roles")
                }

                Section {
                    ForEach(excludedKeywords, id: \.self) { kw in
                        Text(kw).foregroundStyle(.red)
                    }
                    .onDelete { indexSet in
                        excludedKeywords.remove(atOffsets: indexSet)
                        saveKeywordsToStorage()
                        debouncedSync()
                    }

                    HStack {
                        TextField("Add keyword...", text: $newKeyword)
                        Button {
                            guard !newKeyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            excludedKeywords.append(newKeyword.trimmingCharacters(in: .whitespaces))
                            newKeyword = ""
                            saveKeywordsToStorage()
                            debouncedSync()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Excluded Keywords")
                }

                // ── Advanced: Individual Weights ────────────────────
                Section {
                    DisclosureGroup("Fine-Tune Weights", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Reject Below")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(scoreCutoff * 100))%")
                                    .font(.callout.weight(.bold).monospaced())
                                    .foregroundStyle(scoreCutoff < 0.30 ? .green : scoreCutoff < 0.50 ? .orange : .red)
                            }
                            Slider(value: $scoreCutoff, in: 0.10...0.60, step: 0.05)
                                .onChange(of: scoreCutoff) { _, _ in debouncedSync() }
                            HStack {
                                Text("More jobs").font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text("Pickier").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Divider()

                        WeightSlider(
                            label: "Stack Mismatch",
                            detail: "They require a stack you haven't used",
                            value: $convincingPenalty, range: -0.40...0.0, step: 0.05, onChange: debouncedSync
                        )
                        WeightSlider(
                            label: "\"Builders Welcome\"",
                            detail: "They say 'show us what you've built'",
                            value: $convincingBoost, range: 0.0...0.25, step: 0.05, onChange: debouncedSync
                        )
                        WeightSlider(
                            label: "Portfolio-First",
                            detail: "Value shipped products over credentials",
                            value: $portfolioBoost, range: 0.0...0.25, step: 0.05, onChange: debouncedSync
                        )

                        Divider()

                        WeightSlider(
                            label: "Nearby",
                            detail: "Same state / ~1-2hr drive",
                            value: $nearbyPenalty, range: -0.20...0.0, step: 0.01, onChange: debouncedSync
                        )
                        WeightSlider(
                            label: "Regional",
                            detail: "Neighboring state (OH, IN, WI, IL, MN)",
                            value: $regionalPenalty, range: -0.30...0.0, step: 0.01, onChange: debouncedSync
                        )
                        WeightSlider(
                            label: "Relocation",
                            detail: "Requires moving to another US city",
                            value: $relocationPenalty, range: -0.40...0.0, step: 0.05, onChange: debouncedSync
                        )
                        WeightSlider(
                            label: "International",
                            detail: "Job is outside the US",
                            value: $internationalPenalty, range: -0.50...0.0, step: 0.05, onChange: debouncedSync
                        )

                        Divider()

                        WeightSlider(
                            label: "Experience Stretch",
                            detail: "Wants 5+ years professional",
                            value: $experiencePenalty, range: -0.30...0.0, step: 0.05, onChange: debouncedSync
                        )
                        WeightSlider(
                            label: "Credential-Heavy",
                            detail: "FAANG / rigid HR / degree gates",
                            value: $credentialPenalty, range: -0.30...0.0, step: 0.05, onChange: debouncedSync
                        )
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Changing individual weights switches you to \"Custom\" mode.")
                }

                // ── Sync + Backend ──────────────────────────────────
                Section {
                    HStack {
                        Label(syncLabel, systemImage: syncIcon)
                            .foregroundStyle(syncColor)
                        if case .syncing = syncStatus {
                            Spacer()
                            ProgressView()
                        }
                    }
                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.caption.monospaced())
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Changes auto-sync. Scoring engine picks them up on next ingest.")
                }

                // ── Notion Integration ──────────────────────────────
                Section {
                    // Status indicator
                    HStack {
                        Image(systemName: notionConnected ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(notionConnected ? .green : .secondary)
                        Text(notionConnected ? "Connected (\(notionPropertyCount) properties)" : "Not connected")
                            .font(.subheadline)
                        Spacer()
                        if notionConnecting {
                            ProgressView().controlSize(.small)
                        }
                    }

                    // Token field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Integration Token")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        SecureField("ntn_...", text: $notionToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption.monospaced())
                    }

                    // Database ID (pre-filled)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Database ID")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("28649a74...", text: $notionDatabaseId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption.monospaced())
                    }

                    // Error display
                    if let error = notionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Connect button
                    Button {
                        Task { await connectNotion() }
                    } label: {
                        HStack {
                            Image(systemName: notionConnected ? "arrow.triangle.2.circlepath" : "link")
                            Text(notionConnected ? "Reconnect" : "Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(notionToken.trimmingCharacters(in: .whitespaces).isEmpty || notionConnecting)
                } header: {
                    HStack {
                        Text("Notion")
                        Spacer()
                        Link("Get Token ↗", destination: URL(string: "https://www.notion.so/profile/integrations")!)
                            .font(.caption)
                    }
                } footer: {
                    Text("Create an integration at notion.so/profile/integrations, share your database with it, then paste the token here.")
                }

                Section {
                    Button("Reset to Defaults") {
                        apply(.balanced)
                        let defaults = UserPreferences.default
                        minSalary = defaults.minSalary
                        requireRemote = defaults.requireRemote
                        locationPreference = defaults.locationPreference
                        preferredRoles = defaults.preferredRoles
                        excludedKeywords = defaults.excludedKeywords
                        maxSeniorityLevel = defaults.maxSeniorityLevel
                        preferredLocations = defaults.preferredLocations
                        serverURL = "http://Gunnars-Brain-Extension.local:8443"
                        saveRolesToStorage()
                        saveKeywordsToStorage()
                        saveLocationsToStorage()
                        debouncedSync()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    syncBadge
                }
            }
            .onAppear { loadFromStorage() }
            .task { await checkNotionStatus() }
            .overlay(alignment: .top) {
                if showSaveToast {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Saved & synced")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                }
            }
            .animation(.spring(response: 0.4), value: showSaveToast)
        }
    }

    // MARK: - Toolbar Sync Badge

    @ViewBuilder
    private var syncBadge: some View {
        switch syncStatus {
        case .idle:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.secondary)
                .font(.body)
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
                .font(.body)
        case .failed:
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(.red)
                .font(.body)
        }
    }

    // MARK: - Local Persistence for String Arrays

    private func loadFromStorage() {
        if let data = preferredRolesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            preferredRoles = decoded
        } else {
            preferredRoles = UserPreferences.default.preferredRoles
            saveRolesToStorage()
        }

        if let data = excludedKeywordsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            excludedKeywords = decoded
        } else {
            excludedKeywords = UserPreferences.default.excludedKeywords
            saveKeywordsToStorage()
        }

        if let data = preferredLocationsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            preferredLocations = decoded
        } else {
            preferredLocations = UserPreferences.default.preferredLocations
            saveLocationsToStorage()
        }
    }

    private func saveRolesToStorage() {
        if let data = try? JSONEncoder().encode(preferredRoles) {
            preferredRolesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    private func saveKeywordsToStorage() {
        if let data = try? JSONEncoder().encode(excludedKeywords) {
            excludedKeywordsJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    private func saveLocationsToStorage() {
        if let data = try? JSONEncoder().encode(preferredLocations) {
            preferredLocationsJSON = String(data: data, encoding: .utf8) ?? "[\"Kalamazoo, Michigan\"]"
        }
    }

    // MARK: - Debounced Auto-Sync

    private func debouncedSync() {
        pendingSyncTask?.cancel()
        pendingSyncTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await syncPreferences()
        }
    }

    // MARK: - Sync Helpers

    private var syncLabel: String {
        switch syncStatus {
        case .idle: return "Ready"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    private var syncIcon: String {
        switch syncStatus {
        case .idle: return "checkmark.circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var syncColor: Color {
        switch syncStatus {
        case .idle: return .secondary
        case .syncing: return .blue
        case .synced: return .green
        case .failed: return .red
        }
    }

    private func syncPreferences() async {
        syncStatus = .syncing
        do {
            _ = try await APIClient.shared.syncPreferences(currentPreferences)
            syncStatus = .synced
            showSaveToast = true
            try? await Task.sleep(for: .seconds(2))
            showSaveToast = false
            try? await Task.sleep(for: .seconds(1))
            if case .synced = syncStatus { syncStatus = .idle }
        } catch {
            syncStatus = .failed(error.localizedDescription)
            try? await Task.sleep(for: .seconds(5))
            syncStatus = .idle
        }
    }

    // MARK: - Notion

    private func connectNotion() async {
        notionConnecting = true
        notionError = nil
        do {
            let result = try await APIClient.shared.configureNotion(
                token: notionToken.trimmingCharacters(in: .whitespaces),
                databaseId: notionDatabaseId.trimmingCharacters(in: .whitespaces)
            )
            notionConnected = result.status == "connected"
            notionPropertyCount = result.propertyCount ?? 0
        } catch {
            notionConnected = false
            notionError = error.localizedDescription
        }
        notionConnecting = false
    }

    private func checkNotionStatus() async {
        do {
            let status = try await APIClient.shared.fetchNotionStatus()
            notionConnected = status.configured
            notionPropertyCount = status.schema?.count ?? 0
        } catch {
            notionConnected = false
        }
    }

    private var formattedSalary: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: minSalary)) ?? "$\(minSalary)"
    }
}

// MARK: - Preset Pill Button

private struct PresetPill: View {
    let preset: StrictnessPreset
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(preset.emoji)
                    .font(.title2)
                Text(preset.rawValue)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.accentColor : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Weight Slider

private struct WeightSlider: View {
    let label: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: () -> Void

    private var displayValue: String {
        let pct = Int(value * 100)
        if pct > 0 { return "+\(pct)%" }
        if pct < 0 { return "\(pct)%" }
        return "0%"
    }

    private var valueColor: Color {
        if value > 0.01 { return .green }
        if value < -0.01 { return .red }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(displayValue)
                    .font(.callout.weight(.bold).monospaced())
                    .foregroundStyle(valueColor)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $value, in: range, step: step)
                .onChange(of: value) { _, _ in onChange() }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Live Score Simulator

private struct ScoreSimulatorView: View {
    let convincingPenalty: Double
    let convincingBoost: Double
    let nearbyPenalty: Double
    let regionalPenalty: Double
    let relocationPenalty: Double
    let internationalPenalty: Double
    let experiencePenalty: Double
    let credentialPenalty: Double
    let portfolioBoost: Double
    let scoreCutoff: Double

    private struct Scenario {
        let emoji: String
        let name: String
        let baseScore: Double
        let adjustments: [String: Double]
    }

    private var scenarios: [Scenario] {
        [
            Scenario(emoji: "🎯", name: "AI startup — \"show us your apps\"",
                     baseScore: 0.85,
                     adjustments: ["portfolio": portfolioBoost, "builders": convincingBoost]),
            Scenario(emoji: "📍", name: "Grand Rapids office, open stack",
                     baseScore: 0.78,
                     adjustments: ["portfolio": portfolioBoost, "nearby": nearbyPenalty]),
            Scenario(emoji: "🚗", name: "Chicago hybrid, needs React",
                     baseScore: 0.70,
                     adjustments: ["convincing": convincingPenalty, "regional": regionalPenalty]),
            Scenario(emoji: "🤔", name: "Requires React + NYC office",
                     baseScore: 0.65,
                     adjustments: ["convincing": convincingPenalty, "relocation": relocationPenalty]),
            Scenario(emoji: "⚠️", name: "Enterprise, 5yr req, Berlin",
                     baseScore: 0.55,
                     adjustments: ["credential": credentialPenalty, "experience": experiencePenalty, "international": internationalPenalty]),
        ]
    }

    private func finalScore(_ scenario: Scenario) -> Double {
        let adjustmentSum = scenario.adjustments.values.reduce(0, +)
        return min(1.0, max(0.0, scenario.baseScore + adjustmentSum))
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.90 { return .green }
        if score >= 0.80 { return .blue }
        if score >= 0.65 { return .indigo }
        if score >= 0.50 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(scenarios.enumerated()), id: \.offset) { _, scenario in
                let score = finalScore(scenario)
                let rejected = score < scoreCutoff
                HStack(spacing: 8) {
                    Text(scenario.emoji)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scenario.name)
                            .font(.caption)
                            .foregroundStyle(rejected ? .secondary : .primary)
                            .strikethrough(rejected)
                        HStack(spacing: 4) {
                            Text("\(Int(scenario.baseScore * 100))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(Int(score * 100))")
                                .font(.caption.weight(.bold).monospaced())
                                .foregroundStyle(rejected ? .red : scoreColor(score))
                            if rejected {
                                Text("REJECTED")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.15))
                            Capsule()
                                .fill(rejected ? .red.opacity(0.4) : scoreColor(score))
                                .frame(width: max(0, geo.size.width * score))
                        }
                    }
                    .frame(width: 60, height: 8)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: convincingPenalty)
        .animation(.easeInOut(duration: 0.2), value: convincingBoost)
        .animation(.easeInOut(duration: 0.2), value: nearbyPenalty)
        .animation(.easeInOut(duration: 0.2), value: regionalPenalty)
        .animation(.easeInOut(duration: 0.2), value: relocationPenalty)
        .animation(.easeInOut(duration: 0.2), value: internationalPenalty)
        .animation(.easeInOut(duration: 0.2), value: experiencePenalty)
        .animation(.easeInOut(duration: 0.2), value: credentialPenalty)
        .animation(.easeInOut(duration: 0.2), value: portfolioBoost)
        .animation(.easeInOut(duration: 0.2), value: scoreCutoff)
    }
}
