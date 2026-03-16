//
//  JobDetailView.swift
//  LinkedOut
//
//  Full detail view for a job — shows cover letter, pitch, actions.
//

import SwiftUI
import UIKit

struct JobDetailView: View {
    let job: JobPayload
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var jobs: JobsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCoverLetter = false
    @State private var showFullDescription = false
    @State private var showShareConfirm = false
    @State private var copied = false
    @State private var shareStatus: ShareStatus = .idle
    @State private var editingNotes = false
    @State private var noteDraft: String = ""
    @State private var selectedStatus: String = "new"

    private enum ShareStatus { case idle, sharing, shared, failed }

    private var detailFreshnessColor: Color {
        guard let date = job.postedAt else { return .gray }
        let hours = -date.timeIntervalSinceNow / 3600
        if hours < 6 { return .green }
        if hours < 24 { return .blue }
        if hours < 72 { return .orange }
        return .gray
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    // Fit reasons — top-level match signals
                    if let reasons = job.fitReasons, !reasons.isEmpty {
                        fitReasonsSection
                        Divider().padding(.horizontal)
                    }
                    scoreMetaSection
                    Divider().padding(.horizontal)
                    companyIntelSection
                    Divider().padding(.horizontal)
                    pitchSection
                    if job.hasCompanyIntel {
                        Divider().padding(.horizontal)
                        requirementsSection
                    }
                    if !(job.techStack ?? []).isEmpty {
                        Divider().padding(.horizontal)
                        techStackSection
                    }
                    if !(job.dealbreakerWarnings ?? []).isEmpty {
                        Divider().padding(.horizontal)
                        dealbreakerSection
                    }
                    if !(job.redFlags ?? []).isEmpty {
                        Divider().padding(.horizontal)
                        redFlagsSection
                    }
                    if !(job.benefits ?? []).isEmpty {
                        Divider().padding(.horizontal)
                        benefitsSection
                    }
                    Divider().padding(.horizontal)
                    notesSection
                    if !(job.description ?? "").isEmpty {
                        Divider().padding(.horizontal)
                        fullDescriptionSection
                    }
                    Divider().padding(.horizontal)
                    coverLetterSection
                    actionSection
                }
            }
            .navigationTitle("Job Dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: job.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.blue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                noteDraft = job.notes ?? ""
                selectedStatus = job.applicationStatus ?? "new"
            }
        }
    }

    // MARK: - Fit Reasons

    private var fitReasonsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why This Fits You", systemImage: "target")
                .font(.headline)
                .foregroundStyle(.green)

            FlowLayout(spacing: 8) {
                ForEach(job.fitReasons ?? [], id: \.self) { reason in
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                        Text(reason)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(20)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status + Experience tags
            HStack(spacing: 8) {
                if let level = job.experienceLevel, !level.isEmpty, level != "Not specified" {
                    Text(level)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.purple.opacity(0.12))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }
                if let type = job.jobType, !type.isEmpty, type != "Not specified" {
                    Text(type)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                if let stage = job.companyStage, !stage.isEmpty, stage != "Unknown" {
                    Text(stage)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.teal.opacity(0.12))
                        .foregroundStyle(.teal)
                        .clipShape(Capsule())
                }
            }

            Text(job.roleTitle)
                .font(.title.bold())

            Text(job.companyName)
                .font(.title2)
                .foregroundStyle(.secondary)

            // Posted date
            if job.postedAt != nil {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Posted \(job.postedDateDisplay)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(job.freshnessLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(detailFreshnessColor)
                }
            }

            // Links row
            HStack(spacing: 16) {
                if !job.sourceUrl.isEmpty, let url = URL(string: job.sourceUrl) {
                    Link(destination: url) {
                        Label("View Listing", systemImage: "arrow.up.right.square")
                            .font(.subheadline)
                    }
                }
                if let applyUrl = job.applyUrl, !applyUrl.isEmpty, let url = URL(string: applyUrl) {
                    Link(destination: url) {
                        Label("Apply Direct", systemImage: "paperplane.fill")
                            .font(.subheadline)
                    }
                    .tint(.green)
                }
                if let companyUrl = job.companyUrl, !companyUrl.isEmpty, let url = URL(string: companyUrl) {
                    Link(destination: url) {
                        Label("Website", systemImage: "globe")
                            .font(.subheadline)
                    }
                    .tint(.indigo)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Score & Meta

    private var scoreMetaSection: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                ScoreRing(score: job.builderScore, size: 70, lineWidth: 7)
                Text("Builder Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(job.salaryDisplay, systemImage: "dollarsign.circle.fill")
                    .font(.headline)

                Label(job.isRemote ? "Remote" : job.location, systemImage: job.isRemote ? "globe" : "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(job.isRemote ? .green : .primary)

                if let size = job.companySize, !size.isEmpty, size != "Unknown" {
                    Label("\(size) people", systemImage: "person.3.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !job.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(job.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Company Intelligence

    private var companyIntelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Company Intelligence", systemImage: "building.2.fill")
                .font(.headline)

            if let desc = job.companyDescription, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Why Matrix — structured factual assessment
            if let logic = job.logicFit, !logic.isEmpty {
                whyMatrixCard(
                    title: "Logic Fit",
                    icon: "arrow.triangle.branch",
                    color: .blue,
                    text: logic
                )
            }

            if let domain = job.domainLeverage, !domain.isEmpty {
                whyMatrixCard(
                    title: "Domain Leverage",
                    icon: "star.fill",
                    color: .purple,
                    text: domain
                )
            }

            if let risk = job.riskReward, !risk.isEmpty {
                whyMatrixCard(
                    title: "Risk / Reward",
                    icon: "arrow.up.arrow.down",
                    color: .orange,
                    text: risk
                )
            }

            // Fallback: show legacy why_interesting if no Why Matrix
            if job.logicFit == nil || (job.logicFit ?? "").isEmpty,
               let why = job.whyInteresting, !why.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why This Is Interesting")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(why)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
    }

    private func whyMatrixCard(title: String, icon: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - AI Pitch

    private var pitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Assessment", systemImage: "sparkles")
                .font(.headline)

            ForEach(job.pitchBullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 3)

                    Text(bullet.replacingOccurrences(of: "• ", with: ""))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Requirements

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Requirements", systemImage: "checklist")
                .font(.headline)

            if let reqs = job.requirements, !reqs.isEmpty {
                ForEach(reqs, id: \.self) { req in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.primary)
                            .padding(.top, 7)
                        Text(req)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let nices = job.niceToHaves, !nices.isEmpty {
                Text("Nice to Have")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(nices, id: \.self) { nice in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.top, 3)
                        Text(nice)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Tech Stack

    private var techStackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tech Stack", systemImage: "cpu")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(job.techStack ?? [], id: \.self) { tech in
                    Text(tech)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.indigo.opacity(0.1))
                        .foregroundStyle(.indigo)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(20)
    }

    // MARK: - Dealbreaker Warnings

    private var dealbreakerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Heads Up — Be Real With Yourself", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(.red)

            ForEach(job.dealbreakerWarnings ?? [], id: \.self) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 3)
                    Text(warning)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(.red.opacity(0.04))
    }

    // MARK: - Red Flags

    private var redFlagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Watch Out For", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(job.redFlags ?? [], id: \.self) { flag in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 3)
                    Text(flag)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(.orange.opacity(0.03))
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Benefits & Perks", systemImage: "gift.fill")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(job.benefits ?? [], id: \.self) { benefit in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(benefit)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(20)
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your Notes", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                Button(editingNotes ? "Save" : "Edit") {
                    if editingNotes {
                        Task { await saveNotes() }
                    }
                    editingNotes.toggle()
                }
                .font(.subheadline.weight(.medium))
            }

            // Application status picker
            HStack {
                Text("Status:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Status", selection: $selectedStatus) {
                    Text("New").tag("new")
                    Text("Applied").tag("applied")
                    Text("Phone Screen").tag("phone_screen")
                    Text("Interview").tag("interview")
                    Text("Offer").tag("offer")
                    Text("Rejected").tag("rejected")
                }
                .pickerStyle(.menu)
                .onChange(of: selectedStatus) { _, newValue in
                    Task { await updateStatus(newValue) }
                }
            }

            if editingNotes {
                TextEditor(text: $noteDraft)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if !noteDraft.isEmpty {
                Text(noteDraft)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text("Tap Edit to add notes about this opportunity...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(20)
    }

    // MARK: - Full Job Description

    private var fullDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { showFullDescription.toggle() }
            } label: {
                HStack {
                    Label("Full Job Description", systemImage: "doc.plaintext")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showFullDescription ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            if showFullDescription {
                Text(job.description ?? "")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .background(.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
    }

    // MARK: - Cover Letter

    private var coverLetterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { showCoverLetter.toggle() }
            } label: {
                HStack {
                    Label("AI Cover Letter Draft", systemImage: "doc.text")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showCoverLetter ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            if showCoverLetter {
                Text(job.draftedCoverLetter)
                    .font(.body)
                    .padding(16)
                    .background(.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    UIPasteboard.general.string = job.draftedCoverLetter
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy to Clipboard", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.medium))
                }
                .tint(copied ? .green : .blue)
            }
        }
        .padding(20)
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 12) {
            // Primary: Apply Now (opens URL)
            if let applyUrl = job.applyUrl, !applyUrl.isEmpty, let url = URL(string: applyUrl) {
                Link(destination: url) {
                    Label("Apply Now", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else if !job.sourceUrl.isEmpty, let url = URL(string: job.sourceUrl) {
                Link(destination: url) {
                    Label("View & Apply", systemImage: "arrow.up.right.square.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await jobs.performAction(job: job, action: .reject)
                        dismiss()
                    }
                } label: {
                    Label("Pass", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Task {
                        await jobs.performAction(job: job, action: .save)
                        dismiss()
                    }
                } label: {
                    Label("Save", systemImage: "bookmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Button {
                Task {
                    await jobs.performAction(job: job, action: .apply)
                    dismiss()
                }
            } label: {
                Label("Mark as Applied", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if auth.isAuthenticated, auth.profile?.personId != "dev-user" {
                Button {
                    Task { await shareToLinkedIn() }
                } label: {
                    Label(
                        shareStatus == .sharing ? "Sharing..." :
                        shareStatus == .shared ? "Shared!" :
                        shareStatus == .failed ? "Failed" :
                        "Share to LinkedIn",
                        systemImage: shareStatus == .shared ? "checkmark" : "square.and.arrow.up"
                    )
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.indigo.opacity(0.1))
                    .foregroundStyle(shareStatus == .shared ? .green : .indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(shareStatus == .sharing || shareStatus == .shared)
            }

            // Block company
            Button(role: .destructive) {
                blockCompany(job.companyName)
                Task {
                    await jobs.performAction(job: job, action: .reject)
                    dismiss()
                }
            } label: {
                Label("Block \(job.companyName)", systemImage: "nosign")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.red.opacity(0.05))
                    .foregroundStyle(.red.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func blockCompany(_ name: String) {
        let key = "blockedCompaniesJSON"
        var list: [String] = []
        if let data = UserDefaults.standard.string(forKey: key)?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            list = decoded
        }
        if !list.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            list.append(name)
            if let encoded = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(String(data: encoded, encoding: .utf8), forKey: key)
            }
        }
    }

    private func saveNotes() async {
        await jobs.updateNotes(jobId: job.id, notes: noteDraft)
    }

    private func updateStatus(_ status: String) async {
        await jobs.updateStatus(jobId: job.id, status: status)
    }

    private func shareToLinkedIn() async {
        guard let personId = auth.profile?.personId else { return }
        shareStatus = .sharing
        do {
            _ = try await APIClient.shared.shareToLinkedIn(
                personId: personId, jobId: job.id
            )
            shareStatus = .shared
        } catch {
            shareStatus = .failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { shareStatus = .idle }
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
