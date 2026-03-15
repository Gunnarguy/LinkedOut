//
//  NotionDatabaseView.swift
//  LinkedOut
//
//  Full CRUD view for the Notion opportunities database.
//

import SwiftUI

// MARK: - Main Database View

struct NotionDatabaseView: View {
    @State private var jobs: [NotionJob] = []
    @State private var schema: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortField: String = "score"
    @State private var sortAscending = false
    @State private var selectedJob: NotionJob?
    @State private var showCreateSheet = false
    @State private var jobToDelete: NotionJob?
    @State private var isScoring = false
    @State private var scoreProgress: NotionScoreStatus?
    @State private var scoreMessage: String?

    private var filteredJobs: [NotionJob] {
        var result = jobs
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { job in
                (job.name ?? "").lowercased().contains(q) ||
                (job.company ?? "").lowercased().contains(q) ||
                (job.role ?? "").lowercased().contains(q) ||
                (job.status ?? "").lowercased().contains(q) ||
                (job.location ?? "").lowercased().contains(q) ||
                (job.notes ?? "").lowercased().contains(q)
            }
        }
        result.sort { a, b in
            let cmp: Bool
            switch sortField {
            case "score":
                cmp = (a.score ?? 0) < (b.score ?? 0)
            case "company":
                cmp = (a.company ?? "") < (b.company ?? "")
            case "status":
                cmp = (a.status ?? "") < (b.status ?? "")
            default:
                cmp = (a.name ?? "") < (b.name ?? "")
            }
            return sortAscending ? cmp : !cmp
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && jobs.isEmpty {
                ProgressView("Loading Notion database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, jobs.isEmpty {
                ContentUnavailableView {
                    Label("Connection Error", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadData() } }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(filteredJobs) { job in
                        NotionJobRow(job: job)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedJob = job }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    jobToDelete = job
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search jobs...")
        .navigationTitle("Notion Database")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Sort By") {
                        Button { sortField = "score"; sortAscending = false } label: {
                            Label("Score (High → Low)", systemImage: sortField == "score" && !sortAscending ? "checkmark" : "")
                        }
                        Button { sortField = "score"; sortAscending = true } label: {
                            Label("Score (Low → High)", systemImage: sortField == "score" && sortAscending ? "checkmark" : "")
                        }
                        Button { sortField = "company"; sortAscending = true } label: {
                            Label("Company A→Z", systemImage: sortField == "company" ? "checkmark" : "")
                        }
                        Button { sortField = "status"; sortAscending = true } label: {
                            Label("Status", systemImage: sortField == "status" ? "checkmark" : "")
                        }
                    }
                    Section {
                        Button { showCreateSheet = true } label: {
                            Label("New Entry", systemImage: "plus")
                        }
                    }
                    Section {
                        Button {
                            Task { await scoreUnscored(rescoreAll: false) }
                        } label: {
                            Label("Score Unscored", systemImage: "brain")
                        }
                        .disabled(isScoring)

                        Button {
                            Task { await scoreUnscored(rescoreAll: true) }
                        } label: {
                            Label("Re-score All", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isScoring)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await loadData() }
        .task { await loadData() }
        .sheet(item: $selectedJob) { job in
            NavigationStack {
                NotionJobDetailView(
                    job: job,
                    schema: schema,
                    onSave: { updated in
                        if let idx = jobs.firstIndex(where: { $0.id == updated.id }) {
                            jobs[idx] = updated
                        }
                        selectedJob = nil
                    },
                    onDelete: {
                        jobs.removeAll { $0.id == job.id }
                        selectedJob = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                NotionCreateView(schema: schema) { newJob in
                    jobs.insert(newJob, at: 0)
                    showCreateSheet = false
                }
            }
        }
        .alert("Archive this entry?", isPresented: .init(
            get: { jobToDelete != nil },
            set: { if !$0 { jobToDelete = nil } }
        )) {
            Button("Archive", role: .destructive) {
                if let job = jobToDelete {
                    Task { await archiveJob(job) }
                }
            }
            Button("Cancel", role: .cancel) { jobToDelete = nil }
        } message: {
            if let job = jobToDelete {
                Text("Archive \"\(job.name ?? "this entry")\" in Notion? This can be undone from Notion's trash.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isScoring || scoreMessage != nil {
                HStack(spacing: 10) {
                    if isScoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if isScoring, let p = scoreProgress {
                            Text("Scoring \(p.done)/\(p.total)...")
                                .font(.subheadline.weight(.medium))
                            Text("\(p.scored) scored, \(p.skipped) skipped, \(p.errors) errors")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let msg = scoreMessage {
                            Text(msg)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    Spacer()
                    if !isScoring {
                        Button("Dismiss") {
                            withAnimation { scoreMessage = nil }
                        }
                        .font(.caption)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let jobsReq = APIClient.shared.fetchNotionJobs()
            async let schemaReq = APIClient.shared.fetchNotionSchema()
            let (fetchedJobs, schemaResp) = try await (jobsReq, schemaReq)
            jobs = fetchedJobs
            schema = schemaResp.schema
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func archiveJob(_ job: NotionJob) async {
        do {
            _ = try await APIClient.shared.deleteNotionJob(pageId: job.notionPageId)
            jobs.removeAll { $0.id == job.id }
        } catch {
            errorMessage = "Archive failed: \(error.localizedDescription)"
        }
    }

    private func scoreUnscored(rescoreAll: Bool) async {
        isScoring = true
        scoreMessage = nil
        scoreProgress = nil

        do {
            _ = try await APIClient.shared.scoreNotionJobs(rescoreAll: rescoreAll)

            // Poll for progress
            while true {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                let status = try await APIClient.shared.fetchNotionScoreStatus()
                scoreProgress = status
                if !status.running {
                    scoreMessage = "Done! \(status.scored) scored, \(status.skipped) skipped"
                    if status.errors > 0 {
                        scoreMessage! += ", \(status.errors) errors"
                    }
                    // Refresh the list to show new scores
                    await loadData()
                    break
                }
            }
        } catch {
            scoreMessage = "Scoring failed: \(error.localizedDescription)"
        }
        isScoring = false
    }
}

// MARK: - Row View

private struct NotionJobRow: View {
    let job: NotionJob

    var body: some View {
        HStack(spacing: 12) {
            // Score circle
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: 3)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: (job.score ?? 0) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(job.score ?? 0))")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(scoreColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.role ?? job.name ?? "Untitled")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let company = job.company, !company.isEmpty {
                    Text(company)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let status = job.status, !status.isEmpty {
                        Text(status)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(status).opacity(0.12))
                            .foregroundStyle(statusColor(status))
                            .clipShape(Capsule())
                    }
                    if let loc = job.location, !loc.isEmpty {
                        Text(loc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if job.remote == true {
                        Image(systemName: "wifi")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var scoreColor: Color {
        let s = job.score ?? 0
        if s >= 75 { return .green }
        if s >= 55 { return .orange }
        return .red
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "applied": return .blue
        case "saved": return .purple
        case "rejected": return .red
        case "not started": return .orange
        case "interview", "phone_screen": return .green
        case "offer": return .mint
        default: return .secondary
        }
    }
}

// MARK: - Detail/Edit View

struct NotionJobDetailView: View {
    @State var job: NotionJob
    let schema: [String: String]
    var onSave: (NotionJob) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var editedFields: [String: Any] = [:]
    @State private var showDeleteConfirm = false
    @State private var saveError: String?

    // Editable text fields
    @State private var editName: String = ""
    @State private var editRole: String = ""
    @State private var editStatus: String = ""
    @State private var editSalary: String = ""
    @State private var editLocation: String = ""
    @State private var editNotes: String = ""
    @State private var editContact: String = ""
    @State private var editCoverLetter: String = ""
    @State private var editIceBreaker: String = ""
    @State private var editGaps: String = ""
    @State private var editGains: String = ""
    @State private var editTechStack: String = ""
    @State private var editNextStep: String = ""
    @State private var editLastStep: String = ""
    @State private var editEnthusiasm: String = ""

    var body: some View {
        Form {
            Section("Core") {
                editableRow("Company", key: "Company", text: $editName)
                editableRow("Role", key: "Role Title 1", text: $editRole)

                if schema["Status 1"] != nil {
                    Picker("Status", selection: $editStatus) {
                        ForEach(["Not started", "Applied", "Saved", "Rejected",
                                 "Interview", "Phone Screen", "Offer"], id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                }
            }

            Section("Location & Salary") {
                editableRow("Location", key: "Location", text: $editLocation)
                editableRow("Salary Range", key: "Salary Range", text: $editSalary)
            }

            Section("Strategy") {
                if schema["Next Step"] != nil {
                    editableRow("Next Step", key: "Next Step", text: $editNextStep)
                }
                if schema["Last Step"] != nil {
                    editableRow("Last Step", key: "Last Step", text: $editLastStep)
                }
                if schema["Enthusiasm Level"] != nil {
                    editableRow("Enthusiasm", key: "Enthusiasm Level", text: $editEnthusiasm)
                }
                editableRow("Contact", key: "Contact", text: $editContact)
            }

            Section("Analysis") {
                editableRow("Gaps", key: "Gaps", text: $editGaps)
                editableRow("Gains", key: "Gains", text: $editGains)
                editableRow("Tech Stack", key: "Tech Stack Summary", text: $editTechStack)
            }

            if schema["Ice Breaker"] != nil {
                Section("Ice Breaker") {
                    TextEditor(text: $editIceBreaker)
                        .frame(minHeight: 60)
                }
            }

            if schema["Cover Letter"] != nil {
                Section("Cover Letter") {
                    TextEditor(text: $editCoverLetter)
                        .frame(minHeight: 100)
                }
            }

            if let tags = job.tags, !tags.isEmpty {
                Section("Tags") {
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if let stack = job.techStack, !stack.isEmpty {
                Section("Tech Stack") {
                    FlowLayout(spacing: 6) {
                        ForEach(stack, id: \.self) { tech in
                            Text(tech)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.purple.opacity(0.1))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if let summary = job.aiSummary, !summary.isEmpty {
                Section("AI Summary") {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Links") {
                if let url = job.sourceUrl, !url.isEmpty, let link = URL(string: url) {
                    Link(destination: link) {
                        Label("Job Listing", systemImage: "link")
                    }
                }
                if let url = job.applyUrl, !url.isEmpty, let link = URL(string: url) {
                    Link(destination: link) {
                        Label("Apply", systemImage: "paperplane")
                    }
                }
                if let url = job.notionUrl, !url.isEmpty, let link = URL(string: url) {
                    Link(destination: link) {
                        Label("Open in Notion", systemImage: "arrow.up.right.square")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Archive from Notion", systemImage: "archivebox")
                }
            }
        }
        .navigationTitle("Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveChanges() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear { populateFields() }
        .alert("Archive this entry?", isPresented: $showDeleteConfirm) {
            Button("Archive", role: .destructive) {
                Task { await deleteEntry() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if let error = saveError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.red, in: Capsule())
                        .padding(.bottom, 20)
                }
            }
        }
    }

    @ViewBuilder
    private func editableRow(_ label: String, key: String, text: Binding<String>) -> some View {
        if schema[key] != nil {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField(label, text: text)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func populateFields() {
        editName = job.name ?? ""
        editRole = job.role ?? ""
        editStatus = job.status ?? "Not started"
        editSalary = job.salary ?? ""
        editLocation = job.location ?? ""
        editNotes = job.notes ?? ""
        editContact = ""
        editCoverLetter = ""
        editIceBreaker = ""
        editGaps = ""
        editGains = ""
        editTechStack = (job.techStack ?? []).joined(separator: ", ")
        editNextStep = ""
        editLastStep = ""
        editEnthusiasm = ""
    }

    private func buildUpdates() -> [String: Any] {
        var updates: [String: Any] = [:]
        if editName != (job.name ?? "") { updates["Company"] = editName }
        if editRole != (job.role ?? "") { updates["Role Title 1"] = editRole }
        if editStatus != (job.status ?? "") { updates["Status 1"] = editStatus }
        if editSalary != (job.salary ?? "") { updates["Salary Range"] = editSalary }
        if editLocation != (job.location ?? "") { updates["Location"] = editLocation }
        if !editContact.isEmpty { updates["Contact"] = editContact }
        if !editCoverLetter.isEmpty { updates["Cover Letter"] = editCoverLetter }
        if !editIceBreaker.isEmpty { updates["Ice Breaker"] = editIceBreaker }
        if !editGaps.isEmpty { updates["Gaps"] = editGaps }
        if !editGains.isEmpty { updates["Gains"] = editGains }
        let techOrig = (job.techStack ?? []).joined(separator: ", ")
        if editTechStack != techOrig { updates["Tech Stack Summary"] = editTechStack }
        if !editNextStep.isEmpty { updates["Next Step"] = editNextStep }
        if !editLastStep.isEmpty { updates["Last Step"] = editLastStep }
        if !editEnthusiasm.isEmpty { updates["Enthusiasm Level"] = editEnthusiasm }
        return updates
    }

    private func saveChanges() async {
        let updates = buildUpdates()
        guard !updates.isEmpty else { dismiss(); return }
        isSaving = true
        saveError = nil
        do {
            let updated = try await APIClient.shared.updateNotionJob(
                pageId: job.notionPageId,
                properties: updates
            )
            onSave(updated)
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteEntry() async {
        do {
            _ = try await APIClient.shared.deleteNotionJob(pageId: job.notionPageId)
            onDelete()
        } catch {
            saveError = "Archive failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Create View

struct NotionCreateView: View {
    let schema: [String: String]
    var onCreate: (NotionJob) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var status = "Not started"
    @State private var location = ""
    @State private var salary = ""
    @State private var notes = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Required") {
                TextField("Company Name", text: $name)
            }

            Section("Details") {
                if schema["Role Title 1"] != nil {
                    TextField("Role Title", text: $role)
                }
                if schema["Status 1"] != nil {
                    Picker("Status", selection: $status) {
                        ForEach(["Not started", "Applied", "Saved", "Rejected"], id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                }
                if schema["Location"] != nil {
                    TextField("Location", text: $location)
                }
                if schema["Salary Range"] != nil {
                    TextField("Salary Range", text: $salary)
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("New Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await createEntry() }
                } label: {
                    if isCreating {
                        ProgressView()
                    } else {
                        Text("Create")
                    }
                }
                .disabled(name.isEmpty || isCreating)
            }
        }
    }

    private func createEntry() async {
        isCreating = true
        errorMessage = nil

        var properties: [String: Any] = ["Company": name]
        if !role.isEmpty { properties["Role Title 1"] = role }
        if schema["Status 1"] != nil { properties["Status 1"] = status }
        if !location.isEmpty { properties["Location"] = location }
        if !salary.isEmpty { properties["Salary Range"] = salary }
        if !notes.isEmpty { properties["Notes"] = notes }

        do {
            let newJob = try await APIClient.shared.createNotionJob(properties: properties)
            onCreate(newJob)
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
