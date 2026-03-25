//
//  TelemetryView.swift
//  LinkedOut
//
//  Real-time backend telemetry dashboard — shows every process state,
//  LLM config, store stats, and live logs.
//

import SwiftUI

struct TelemetryView: View {
    @State private var telemetry: TelemetryResponse?
    @State private var error: String?
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?
    @State private var showFullLogs = false

    var body: some View {
        Group {
            if let t = telemetry {
                List {
                    serverSection(t.server)
                    ingestSection(t.ingest)
                    rescoreSection(t.rescore)
                    storeSection(t.store)
                    llmSection(t.llm)
                    notionSection(t.notion)
                    logsSection(t.logs)
                }
                .listStyle(.insetGrouped)
            } else if let error {
                ContentUnavailableView {
                    Label("Connection Error", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            } else {
                ProgressView("Connecting to backend…")
            }
        }
        .navigationTitle("Telemetry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Live indicator
                    if autoRefresh {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(.green.opacity(0.4), lineWidth: 2)
                                    .scaleEffect(1.5)
                            )
                    }
                    Toggle("Live", isOn: $autoRefresh)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.7)
                }
            }
        }
        .task { startPolling() }
        .onDisappear { refreshTask?.cancel() }
        .onChange(of: autoRefresh) {
            if autoRefresh { startPolling() } else { refreshTask?.cancel() }
        }
    }

    // MARK: - Sections

    private func serverSection(_ s: TelemetryServer) -> some View {
        Section {
            StatusRow(label: "Uptime", value: s.uptimeHuman, icon: "clock", tint: .green)
            StatusRow(label: "Host", value: s.hostname, icon: "server.rack")
            StatusRow(label: "Port", value: "\(s.port)", icon: "network")
            StatusRow(label: "Platform", value: s.render ? "Render (cloud)" : "Local Docker", icon: "cloud", tint: s.render ? .blue : .secondary)
            StatusRow(label: "Debug", value: s.debug ? "ON" : "OFF", icon: "ladybug", tint: s.debug ? .orange : .secondary)
            StatusRow(label: "Python", value: s.pythonVersion, icon: "chevron.left.forwardslash.chevron.right")
        } header: {
            Label("Server", systemImage: "server.rack")
        }
    }

    private func ingestSection(_ i: TelemetryIngest) -> some View {
        Section {
            // Phase indicator
            let p = i.progress
            HStack {
                phaseIcon(p.phase)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phase: **\(p.phase.capitalized)**")
                    if p.phase == "scoring" && p.totalBatches > 0 {
                        Text("Batch \(p.batch)/\(p.totalBatches)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if p.phase == "scoring" || p.phase == "fetching" || p.phase == "deduping" {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if p.phase == "scoring" && p.totalBatches > 0 {
                ProgressView(value: Double(p.batch), total: Double(p.totalBatches))
                    .tint(.blue)
            }

            if let stage = p.currentStage,
               let item = p.currentItem,
               let total = p.currentTotal,
               let title = p.currentTitle,
               !title.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Listing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(stage.capitalized) \(item)/\(total): \(title)")
                        .font(.subheadline)
                    if let company = p.currentCompany, !company.isEmpty {
                        Text(company)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Counters
            if p.fetched > 0 || p.phase != "idle" {
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 8) {
                    CounterCell(label: "Fetched", count: p.fetched, color: .blue)
                    CounterCell(label: "New", count: p.newAfterDedup, color: .cyan)
                    CounterCell(label: "Triaged", count: p.triaged ?? 0, color: .mint)
                    CounterCell(label: "Scored", count: p.scored, color: .indigo)
                    CounterCell(label: "To Score", count: p.toScore ?? 0, color: .purple)
                    CounterCell(label: "Queued", count: p.queued, color: .green)
                    CounterCell(label: "Rejected", count: p.rejected, color: .orange)
                    CounterCell(label: "Low Score", count: p.lowScore, color: .yellow)
                }
                .padding(.vertical, 4)
            }

            // Timing
            StatusRow(label: "Lock Held", value: i.lockHeld ? "YES" : "no", icon: "lock", tint: i.lockHeld ? .red : .secondary)
            StatusRow(label: "Periodic Task", value: i.periodicTaskAlive ? "ALIVE" : "dead", icon: "arrow.triangle.2.circlepath", tint: i.periodicTaskAlive ? .green : .red)
            StatusRow(label: "Manual Task", value: i.manualTaskAlive ? "RUNNING" : "idle", icon: "hand.tap", tint: i.manualTaskAlive ? .blue : .secondary)

            if let dur = p.lastDurationS {
                StatusRow(label: "Last Duration", value: formatDuration(dur), icon: "stopwatch")
            }
            StatusRow(label: "Cycles Done", value: "\(p.cyclesCompleted)", icon: "repeat")
            if p.errors > 0 {
                StatusRow(label: "Errors", value: "\(p.errors)", icon: "exclamationmark.triangle", tint: .red)
            }
        } header: {
            Label("Ingest Pipeline", systemImage: "arrow.down.doc")
        }
    }

    private func rescoreSection(_ r: TelemetryRescore) -> some View {
        Section {
            StatusRow(
                label: "Status",
                value: r.running ? "RUNNING (\(r.done)/\(r.total))" : (r.total > 0 ? "Done (\(r.done)/\(r.total))" : "Idle"),
                icon: "arrow.triangle.2.circlepath",
                tint: r.running ? .blue : .secondary
            )
            if r.running && r.total > 0 {
                ProgressView(value: Double(r.done), total: Double(r.total))
                    .tint(.purple)
            }
            if r.errors > 0 {
                StatusRow(label: "Errors", value: "\(r.errors)", icon: "exclamationmark.triangle", tint: .red)
            }
        } header: {
            Label("Re-Score", systemImage: "arrow.up.arrow.down")
        }
    }

    private func storeSection(_ s: TelemetryStore) -> some View {
        Section {
            HStack(spacing: 16) {
                BucketPill(label: "Pending", count: s.pending, color: .blue)
                BucketPill(label: "Applied", count: s.applied, color: .green)
                BucketPill(label: "Saved", count: s.saved, color: .purple)
                BucketPill(label: "Rejected", count: s.rejected, color: .red)
            }
            .padding(.vertical, 4)

            if let seen = s.seenUrls {
                StatusRow(label: "Seen URLs", value: "\(seen)", icon: "eye")
            }
            StatusRow(label: "Data Dir", value: s.dataDir, icon: "folder")
        } header: {
            Label("Job Store", systemImage: "tray.2")
        }
    }

    private func llmSection(_ l: TelemetryLLM) -> some View {
        Section {
            StatusRow(label: "Provider", value: l.provider.capitalized, icon: "brain")
            StatusRow(label: "Gemini Pro", value: l.geminiModel, icon: "sparkle")
            StatusRow(label: "Gemini Flash", value: l.geminiFlashModel, icon: "bolt")
            StatusRow(label: "OpenAI Model", value: l.openaiModel, icon: "circle.hexagonpath")
            StatusRow(label: "Gemini Key", value: l.hasGeminiKey ? "SET" : "MISSING", icon: "key", tint: l.hasGeminiKey ? .green : .red)
            StatusRow(label: "OpenAI Key", value: l.hasOpenaiKey ? "SET" : "MISSING", icon: "key", tint: l.hasOpenaiKey ? .green : .red)
        } header: {
            Label("LLM Config", systemImage: "cpu")
        }
    }

    private func notionSection(_ n: TelemetryNotion) -> some View {
        Section {
            StatusRow(label: "Configured", value: n.configured ? "YES" : "NO", icon: "checkmark.circle", tint: n.configured ? .green : .secondary)
            StatusRow(label: "Sync Task", value: n.syncTaskAlive ? "RUNNING" : "idle", icon: "arrow.triangle.2.circlepath", tint: n.syncTaskAlive ? .blue : .secondary)
            StatusRow(label: "Score Task", value: n.scoreTaskAlive ? "RUNNING" : "idle", icon: "star", tint: n.scoreTaskAlive ? .blue : .secondary)
        } header: {
            Label("Notion", systemImage: "doc.richtext")
        }
    }

    private func logsSection(_ logs: [String]) -> some View {
        Section {
            if logs.isEmpty {
                Text("No recent logs")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                let displayed = showFullLogs ? logs : Array(logs.suffix(15))
                ForEach(Array(displayed.enumerated()), id: \.offset) { _, line in
                    logLine(line)
                }
                if !showFullLogs && logs.count > 15 {
                    Button("Show all \(logs.count) lines") {
                        showFullLogs = true
                    }
                    .font(.caption)
                }
            }
        } header: {
            Label("Live Logs (\(logs.count))", systemImage: "text.alignleft")
        }
    }

    // MARK: - Components

    private func logLine(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(logColor(line))
            .lineLimit(3)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
    }

    private func logColor(_ line: String) -> Color {
        if line.contains("ERROR") || line.contains("FAILED") { return .red }
        if line.contains("WARNING") { return .orange }
        if line.contains("QUEUED") || line.contains("COMPLETE") { return .green }
        if line.contains("REJECTED") || line.contains("LOW SCORE") { return .yellow }
        if line.contains("BATCH") || line.contains("RESCORE") { return .cyan }
        return .primary
    }

    @ViewBuilder
    private func phaseIcon(_ phase: String) -> some View {
        switch phase {
        case "idle":
            Image(systemName: "moon.zzz").foregroundStyle(.secondary).font(.title3)
        case "fetching":
            Image(systemName: "icloud.and.arrow.down").foregroundStyle(.blue).font(.title3)
        case "deduping":
            Image(systemName: "doc.on.doc").foregroundStyle(.cyan).font(.title3)
        case "scoring":
            Image(systemName: "brain").foregroundStyle(.purple).font(.title3)
        case "complete":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
        case "error":
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).font(.title3)
        default:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).font(.title3)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            }
        }
    }

    private func load() async {
        do {
            telemetry = try await APIClient.shared.fetchTelemetry()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func formatDuration(_ s: Double) -> String {
        if s < 60 { return String(format: "%.1fs", s) }
        let mins = Int(s) / 60
        let secs = Int(s) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - Reusable cells

private struct StatusRow: View {
    let label: String
    let value: String
    var icon: String = ""
    var tint: Color = .primary

    var body: some View {
        HStack {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 20)
            }
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(tint == .primary ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.subheadline)
    }
}

private struct CounterCell: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BucketPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        TelemetryView()
    }
}
