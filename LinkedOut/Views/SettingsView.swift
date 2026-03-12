//
//  SettingsView.swift
//  LinkedOut
//
//  Job preferences & scoring intelligence dashboard.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("minSalary") private var minSalary: Int = 90000
    @AppStorage("requireRemote") private var requireRemote: Bool = true
    @AppStorage("locationPreference") private var locationPreference: String = "Remote"
    @AppStorage("serverURL") private var serverURL: String = "http://Gunnars-Brain-Extension.local:8443"
    @AppStorage("preferredRolesJSON") private var preferredRolesJSON: String = "[]"
    @AppStorage("excludedKeywordsJSON") private var excludedKeywordsJSON: String = "[]"

    // ── Scoring Weights ──
    @AppStorage("scoreCutoff") private var scoreCutoff: Double = 0.35
    @AppStorage("convincingPenalty") private var convincingPenalty: Double = -0.20
    @AppStorage("convincingBoost") private var convincingBoost: Double = 0.10
    @AppStorage("relocationPenalty") private var relocationPenalty: Double = -0.15
    @AppStorage("internationalPenalty") private var internationalPenalty: Double = -0.25
    @AppStorage("experiencePenalty") private var experiencePenalty: Double = -0.10
    @AppStorage("credentialPenalty") private var credentialPenalty: Double = -0.15
    @AppStorage("portfolioBoost") private var portfolioBoost: Double = 0.10
    @AppStorage("maxSeniorityLevel") private var maxSeniorityLevel: String = "Mid"

    @State private var preferredRoles: [String] = []
    @State private var excludedKeywords: [String] = []
    @State private var newRole = ""
    @State private var newKeyword = ""
    @State private var syncStatus: SyncStatus = .idle
    @State private var pendingSyncTask: Task<Void, Never>?

    private enum SyncStatus { case idle, syncing, synced, failed(String) }

    private var currentPreferences: UserPreferences {
        UserPreferences(
            minSalary: minSalary,
            requireRemote: requireRemote,
            preferredRoles: preferredRoles,
            excludedKeywords: excludedKeywords,
            locationPreference: locationPreference,
            scoreCutoff: scoreCutoff,
            convincingPenalty: convincingPenalty,
            convincingBoost: convincingBoost,
            relocationPenalty: relocationPenalty,
            internationalPenalty: internationalPenalty,
            experiencePenalty: experiencePenalty,
            credentialPenalty: credentialPenalty,
            portfolioBoost: portfolioBoost,
            maxSeniorityLevel: maxSeniorityLevel
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Live Score Simulator ────────────────────────────
                Section {
                    ScoreSimulatorView(
                        convincingPenalty: convincingPenalty,
                        convincingBoost: convincingBoost,
                        relocationPenalty: relocationPenalty,
                        internationalPenalty: internationalPenalty,
                        experiencePenalty: experiencePenalty,
                        credentialPenalty: credentialPenalty,
                        portfolioBoost: portfolioBoost,
                        scoreCutoff: scoreCutoff
                    )
                } header: {
                    Text("Live Score Preview")
                } footer: {
                    Text("See how your adjustments affect example job scenarios. Drag the sliders below to tune.")
                }

                // ── Score Cutoff ────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reject Below")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(scoreCutoff * 100))%")
                                .font(.title3.weight(.bold).monospaced())
                                .foregroundStyle(scoreCutoff < 0.30 ? .green : scoreCutoff < 0.50 ? .orange : .red)
                        }
                        Slider(value: $scoreCutoff, in: 0.10...0.60, step: 0.05)
                            .onChange(of: scoreCutoff) { _, _ in debouncedSync() }
                        HStack {
                            Text("More jobs").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Higher quality").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Quality Threshold")
                } footer: {
                    Text("Jobs scoring below this are auto-rejected. Lower = more volume, higher = pickier.")
                }

                // ── Convincing Penalty/Boost ────────────────────────
                Section {
                    WeightSlider(
                        label: "Hard Stack Mismatch",
                        detail: "Penalty when they require a stack you haven't used",
                        value: $convincingPenalty,
                        range: -0.40...0.0,
                        step: 0.05,
                        onChange: debouncedSync
                    )
                    WeightSlider(
                        label: "Builders Welcome Boost",
                        detail: "Bonus when they say \"show us what you've built\"",
                        value: $convincingBoost,
                        range: 0.0...0.25,
                        step: 0.05,
                        onChange: debouncedSync
                    )
                    WeightSlider(
                        label: "Portfolio / Shipped Products",
                        detail: "Bonus when they value shipped products over credentials",
                        value: $portfolioBoost,
                        range: 0.0...0.25,
                        step: 0.05,
                        onChange: debouncedSync
                    )
                } header: {
                    Text("\"Convincing Required\" Weights")
                } footer: {
                    Text("The core question: would they already want you, or would you have to sell yourself?")
                }

                // ── Location Weights ────────────────────────────────
                Section {
                    WeightSlider(
                        label: "Relocation (Other US City)",
                        detail: "Penalty for jobs requiring relocation to NYC, Austin, etc.",
                        value: $relocationPenalty,
                        range: -0.40...0.0,
                        step: 0.05,
                        onChange: debouncedSync
                    )
                    WeightSlider(
                        label: "International",
                        detail: "Penalty for jobs in London, Berlin, etc.",
                        value: $internationalPenalty,
                        range: -0.50...0.0,
                        step: 0.05,
                        onChange: debouncedSync
                    )
                } header: {
                    Text("Location Weights")
                }

                // ── Experience & Credentials ────────────────────────
                Section {
                    WeightSlider(
                        label: "Experience Stretch",
                        detail: "Penalty when they want 5+ years professional",
                        value: $experiencePenalty,
                        range: -0.30...0.0,
                        step: 0.05,
                        onChange: debouncedSync
                    )
                    WeightSlider(
                        label: "Credential-Heavy Culture",
                        detail: "Penalty for rigid HR, enterprise, FAANG-style hiring",
                        value: $credentialPenalty,
                        range: -0.30...0.0,
                        step: 0.05,
                        onChange: debouncedSync
                    )

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
                } header: {
                    Text("Experience & Credentials")
                } footer: {
                    Text("Seniority filter: roles above your max level are auto-rejected in triage.")
                }

                // ── Salary ──────────────────────────────────────────
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Minimum")
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
                } header: {
                    Text("Salary")
                }

                // ── Location ────────────────────────────────────────
                Section {
                    Toggle("Remote Only", isOn: $requireRemote)
                        .onChange(of: requireRemote) { _, _ in debouncedSync() }

                    if !requireRemote {
                        TextField("Preferred Location", text: $locationPreference)
                            .onSubmit { debouncedSync() }
                    }
                } header: {
                    Text("Location")
                }

                // ── Preferred Roles ─────────────────────────────────
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

                // ── Excluded Keywords ───────────────────────────────
                Section {
                    ForEach(excludedKeywords, id: \.self) { kw in
                        Text(kw)
                            .foregroundStyle(.red)
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

                // ── Backend ─────────────────────────────────────────
                Section {
                    HStack {
                        Label(syncLabel, systemImage: syncIcon)
                            .foregroundStyle(syncColor)
                        if case .syncing = syncStatus {
                            Spacer()
                            ProgressView()
                        }
                    }
                } header: {
                    Text("Sync Status")
                } footer: {
                    Text("Changes auto-sync to the backend. The scoring engine picks them up on the next ingest.")
                }

                Section("Backend") {
                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Button("Reset to Defaults") {
                        let defaults = UserPreferences.default
                        minSalary = defaults.minSalary
                        requireRemote = defaults.requireRemote
                        locationPreference = defaults.locationPreference
                        preferredRoles = defaults.preferredRoles
                        excludedKeywords = defaults.excludedKeywords
                        scoreCutoff = defaults.scoreCutoff
                        convincingPenalty = defaults.convincingPenalty
                        convincingBoost = defaults.convincingBoost
                        relocationPenalty = defaults.relocationPenalty
                        internationalPenalty = defaults.internationalPenalty
                        experiencePenalty = defaults.experiencePenalty
                        credentialPenalty = defaults.credentialPenalty
                        portfolioBoost = defaults.portfolioBoost
                        maxSeniorityLevel = defaults.maxSeniorityLevel
                        serverURL = "http://Gunnars-Brain-Extension.local:8443"
                        saveRolesToStorage()
                        saveKeywordsToStorage()
                        debouncedSync()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadFromStorage() }
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

    private var isSyncing: Bool {
        if case .syncing = syncStatus { return true }
        return false
    }

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
            try? await Task.sleep(for: .seconds(3))
            if case .synced = syncStatus { syncStatus = .idle }
        } catch {
            syncStatus = .failed(error.localizedDescription)
            try? await Task.sleep(for: .seconds(5))
            syncStatus = .idle
        }
    }

    private var formattedSalary: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: minSalary)) ?? "$\(minSalary)"
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
            Scenario(emoji: "🎯", name: "Dream: AI startup, 'show us your apps'",
                     baseScore: 0.85,
                     adjustments: ["portfolio": portfolioBoost, "builders": convincingBoost]),
            Scenario(emoji: "💪", name: "Good: Founding eng, remote, no stack req",
                     baseScore: 0.78,
                     adjustments: ["portfolio": portfolioBoost]),
            Scenario(emoji: "🤔", name: "Stretch: Requires React, NYC office",
                     baseScore: 0.65,
                     adjustments: ["convincing": convincingPenalty, "relocation": relocationPenalty]),
            Scenario(emoji: "⚠️", name: "Risky: Enterprise, 5yr req, Berlin",
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
                    // Mini score bar
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
        .animation(.easeInOut(duration: 0.2), value: relocationPenalty)
        .animation(.easeInOut(duration: 0.2), value: internationalPenalty)
        .animation(.easeInOut(duration: 0.2), value: experiencePenalty)
        .animation(.easeInOut(duration: 0.2), value: credentialPenalty)
        .animation(.easeInOut(duration: 0.2), value: portfolioBoost)
        .animation(.easeInOut(duration: 0.2), value: scoreCutoff)
    }
}

// MARK: - Helper Views

private struct StrengthRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HardFilterRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.red)
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct PenaltyRow: View {
    let label: String
    let penalty: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(penalty)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(color)
        }
        .padding(.vertical, 1)
    }
}

private struct ScoreTierRow: View {
    let range: String
    let emoji: String
    let label: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(range)
                        .font(.caption.weight(.bold).monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
