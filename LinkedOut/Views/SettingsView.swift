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
    @State private var preferredRoles: [String] = []
    @State private var excludedKeywords: [String] = []
    @State private var newRole = ""
    @State private var newKeyword = ""
    @State private var syncStatus: SyncStatus = .idle
    @State private var showingScoringDetail = false
    @State private var showingHardFilters = false

    private enum SyncStatus { case idle, syncing, synced, failed(String) }

    private var currentPreferences: UserPreferences {
        UserPreferences(
            minSalary: minSalary,
            requireRemote: requireRemote,
            preferredRoles: preferredRoles,
            excludedKeywords: excludedKeywords,
            locationPreference: locationPreference
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Scoring Brain Overview ──────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Scoring Engine")
                                    .font(.headline)
                                Text("Calibrated to your real profile")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Your identity card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("THE ENGINE KNOWS YOU AS")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .tracking(1)

                            Text("AI orchestrator — does NOT write code by hand. Ships products by directing LLMs to generate all code while handling architecture, product design, and systems thinking. 5 shipped products (4 App Store + LinkedOut). 382 commits/year. Working in healthcare ops at VA Palo Alto. Looking for companies that already want someone like this — no convincing required.")
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.85))
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Scoring Intelligence")
                }

                // ── Your Weapons ────────────────────────────────────
                Section {
                    StrengthRow(icon: "sparkles", color: .purple, title: "AI Orchestration",
                                detail: "THE core skill — directs LLMs to ship complete products at extreme velocity")
                    StrengthRow(icon: "hammer.fill", color: .orange, title: "RAG / Embeddings / Vector Search",
                                detail: "OpenIntelligence, OpenCone, OpenAssistant — 3 production RAG systems")
                    StrengthRow(icon: "shippingbox.fill", color: .green, title: "5 Shipped Products",
                                detail: "4 App Store + LinkedOut (full-stack). Not tutorials — real products.")
                    StrengthRow(icon: "link", color: .indigo, title: "MCP / Agent Tooling",
                                detail: "OpenResponses — tool-use, multi-model, Computer Use")
                    StrengthRow(icon: "brain", color: .pink, title: "Systems Thinking",
                                detail: "Architecture, data flow, integration design — stack-agnostic")
                    StrengthRow(icon: "cross.case.fill", color: .red, title: "Healthcare Domain",
                                detail: "HIPAA, surgical workflows, medical devices, VA system")
                } header: {
                    Text("Your Weapons (score boosters)")
                } footer: {
                    Text("Companies that value these skills — especially AI orchestration and shipped products — score highest.")
                }

                // ── Hard Filters (instant reject) ───────────────────
                Section {
                    HardFilterRow(icon: "xmark.shield.fill", text: "Senior / Staff / Lead / Principal / Director titles")
                    HardFilterRow(icon: "xmark.shield.fill", text: "CS degree required (no equivalent accepted)")
                    HardFilterRow(icon: "xmark.shield.fill", text: "7+ years professional SWE required")
                    HardFilterRow(icon: "xmark.shield.fill", text: "5+ years required with no flexibility")
                    HardFilterRow(icon: "xmark.shield.fill", text: "Non-tech roles (sales, marketing, HR, legal)")
                } header: {
                    Text("Hard Filters (instant reject)")
                } footer: {
                    Text("These never reach your queue. The AI bouncer kills them on sight — no exceptions.")
                }

                // ── Score Penalties (transparent) ───────────────────
                Section {
                    DisclosureGroup("Location Penalties") {
                        PenaltyRow(label: "Remote / Remote-first", penalty: "None", color: .green)
                        PenaltyRow(label: "Bay Area (SF, Palo Alto, SJ)", penalty: "−3%", color: .yellow)
                        PenaltyRow(label: "Hybrid Bay Area", penalty: "−5%", color: .yellow)
                        PenaltyRow(label: "Other US (NYC, Austin, Seattle…)", penalty: "−15%", color: .orange)
                        PenaltyRow(label: "International (London, Berlin…)", penalty: "−25%", color: .red)
                    }

                    DisclosureGroup("\"Convincing Required\" Penalties") {
                        PenaltyRow(label: "Company wants builders / portfolio-first", penalty: "+10%", color: .green)
                        PenaltyRow(label: "Any modern framework / stack-agnostic", penalty: "+10%", color: .green)
                        PenaltyRow(label: "Stack preferred but not required", penalty: "−5%", color: .yellow)
                        PenaltyRow(label: "Hard stack req, no learner signal", penalty: "−15 to −25%", color: .red)
                        PenaltyRow(label: "Enterprise / rigid HR / credential-heavy", penalty: "−15%", color: .red)
                    }

                    DisclosureGroup("Experience Reality Penalties") {
                        PenaltyRow(label: "1-3 years or any experience", penalty: "None", color: .green)
                        PenaltyRow(label: "3-5 years professional", penalty: "−5% + flagged", color: .yellow)
                        PenaltyRow(label: "5+ years with flexibility", penalty: "−10% + flagged", color: .orange)
                        PenaltyRow(label: "CS degree preferred", penalty: "−3% + flagged", color: .yellow)
                        PenaltyRow(label: "CS degree or equivalent", penalty: "−5% + flagged", color: .yellow)
                        PenaltyRow(label: "Elite hiring bar (FAANG, quant)", penalty: "−10%", color: .red)
                    }
                } header: {
                    Text("Score Adjustments (fully transparent)")
                } footer: {
                    Text("Every score you see has these adjustments baked in. No hidden inflation — what you see is what you get.")
                }

                // ── Score Tiers Explained ───────────────────────────
                Section {
                    ScoreTierRow(range: "90-100", emoji: "🎯", label: "Dream Fit",
                                 detail: "They already want someone like you. No convincing needed. ~3-5% of jobs.", color: .green)
                    ScoreTierRow(range: "80-89", emoji: "💪", label: "Strong Fit",
                                 detail: "Culture signals say they'd be excited by your profile. ~10% of jobs.", color: .blue)
                    ScoreTierRow(range: "65-79", emoji: "👍", label: "Solid Option",
                                 detail: "Interesting company, some alignment. Minor unknowns. ~15% of jobs.", color: .indigo)
                    ScoreTierRow(range: "50-64", emoji: "🤔", label: "Stretch",
                                 detail: "You'd need to do some convincing. ~15% of jobs.", color: .orange)
                    ScoreTierRow(range: "35-49", emoji: "🎲", label: "Long Shot",
                                 detail: "Significant convincing needed but compelling mission.", color: .red)
                } header: {
                    Text("What the scores mean")
                } footer: {
                    Text("Below 35 never reaches your queue. The key question: would they already want you, or would you have to convince them?");
                }

                // ── Editable Preferences ────────────────────────────
                Section("Salary") {
                    VStack(alignment: .leading) {
                        Text("Minimum: \(formattedSalary)")
                            .font(.headline)
                        Slider(
                            value: Binding(
                                get: { Double(minSalary) },
                                set: { minSalary = Int($0) }
                            ),
                            in: 50_000...300_000,
                            step: 5_000
                        )
                    }
                }

                Section("Location") {
                    Toggle("Remote Only", isOn: $requireRemote)

                    if !requireRemote {
                        TextField("Preferred Location", text: $locationPreference)
                    }
                }

                Section("Preferred Roles") {
                    ForEach(preferredRoles, id: \.self) { role in
                        Text(role)
                    }
                    .onDelete { indexSet in
                        preferredRoles.remove(atOffsets: indexSet)
                        saveRolesToStorage()
                    }

                    HStack {
                        TextField("Add role...", text: $newRole)
                        Button {
                            guard !newRole.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            preferredRoles.append(newRole.trimmingCharacters(in: .whitespaces))
                            newRole = ""
                            saveRolesToStorage()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newRole.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Excluded Keywords") {
                    ForEach(excludedKeywords, id: \.self) { kw in
                        Text(kw)
                            .foregroundStyle(.red)
                    }
                    .onDelete { indexSet in
                        excludedKeywords.remove(atOffsets: indexSet)
                        saveKeywordsToStorage()
                    }

                    HStack {
                        TextField("Add keyword...", text: $newKeyword)
                        Button {
                            guard !newKeyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            excludedKeywords.append(newKeyword.trimmingCharacters(in: .whitespaces))
                            newKeyword = ""
                            saveKeywordsToStorage()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // ── Sync & Backend ──────────────────────────────────
                Section {
                    Button {
                        Task { await syncPreferences() }
                    } label: {
                        HStack {
                            Label(syncLabel, systemImage: syncIcon)
                            if case .syncing = syncStatus {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncing)
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Push your preferences to the backend. The AI scoring engine applies them on the next ingest cycle.")
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
                        serverURL = "http://Gunnars-Brain-Extension.local:8443"
                        saveRolesToStorage()
                        saveKeywordsToStorage()
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

    // MARK: - Sync Helpers

    private var isSyncing: Bool {
        if case .syncing = syncStatus { return true }
        return false
    }

    private var syncLabel: String {
        switch syncStatus {
        case .idle: return "Sync Preferences"
        case .syncing: return "Syncing..."
        case .synced: return "Synced!"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    private var syncIcon: String {
        switch syncStatus {
        case .idle: return "arrow.triangle.2.circlepath"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
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
