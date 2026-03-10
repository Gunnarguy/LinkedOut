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
    @State private var showShareConfirm = false
    @State private var copied = false
    @State private var shareStatus: ShareStatus = .idle

    private enum ShareStatus { case idle, sharing, shared, failed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    headerSection

                    Divider().padding(.horizontal)

                    // Score & Meta
                    metaSection

                    Divider().padding(.horizontal)

                    // AI Pitch
                    pitchSection

                    Divider().padding(.horizontal)

                    // Cover Letter
                    coverLetterSection

                    // Actions
                    actionSection
                }
            }
            .navigationTitle("Job Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(job.roleTitle)
                .font(.title.bold())

            Text(job.companyName)
                .font(.title2)
                .foregroundStyle(.secondary)

            if !job.sourceUrl.isEmpty {
                Link(destination: URL(string: job.sourceUrl) ?? URL(string: "https://linkedin.com")!) {
                    Label("View Original", systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            }
        }
        .padding(20)
    }

    private var metaSection: some View {
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

    private var coverLetterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { showCoverLetter.toggle() }
            } label: {
                HStack {
                    Label("Cover Letter Draft", systemImage: "doc.text")
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

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        await jobs.performAction(jobId: job.id, action: .reject)
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
                        await jobs.performAction(jobId: job.id, action: .save)
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
                    await jobs.performAction(jobId: job.id, action: .apply)
                    dismiss()
                }
            } label: {
                Label("Apply", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
        }
        .padding(20)
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
