//
//  ApplyReviewSheet.swift
//  LinkedOut
//
//  Pre-apply review — surfaces cover letter, fit reasons, and dealbreakers
//  so you can copy your pitch before opening the application.
//

import SwiftUI

struct ApplyReviewSheet: View {
    let job: JobPayload
    let onApply: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject var auth: AuthViewModel
    @State private var copied = false
    @State private var safariWrapper: URLWrapper? = nil
    @State private var isShowingShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(job.roleTitle)
                            .font(.title2.bold())
                        Text(job.companyName)
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ScoreRing(score: job.effectiveBuilderScore, size: 40, lineWidth: 4)
                            Text(job.salaryDisplay)
                                .font(.subheadline.weight(.medium))
                            if job.isRemote {
                                Label("Remote", systemImage: "globe")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)

                    Divider()

                    // Fit reasons
                    if let reasons = job.fitReasons, !reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Why This Fits", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            ForEach(reasons, id: \.self) { reason in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .padding(.top, 2)
                                    Text(reason)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(20)

                        Divider()
                    }

                    // Dealbreaker check
                    if !job.displayDealbreakerWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Heads Up", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            ForEach(job.displayDealbreakerWarnings, id: \.self) { warning in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .padding(.top, 2)
                                    Text(warning)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(20)

                        Divider()
                    }

                    // Cover letter
                    if !job.draftedCoverLetter.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Your Cover Letter", systemImage: "doc.text")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = job.draftedCoverLetter
                                    copied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                                } label: {
                                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                        .font(.subheadline.weight(.medium))
                                }
                                .tint(copied ? .green : .blue)
                            }

                            Text(job.draftedCoverLetter)
                                .font(.body)
                                .padding(16)
                                .background(.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(20)

                        Divider()
                    }

                    // Action buttons
                    VStack(spacing: 12) {
                        let applyURL = job.applyUrl ?? job.sourceUrl
                        if let url = URL(string: applyURL) {
                            Button {
                                // Auto-copy pitch summary/cover letter to clipboard first
                                let textToCopy = job.draftedCoverLetter.isEmpty ? job.aiPitchSummary : job.draftedCoverLetter
                                if !textToCopy.isEmpty {
                                    UIPasteboard.general.string = textToCopy
                                }

                                safariWrapper = URLWrapper(url: url)
                                onApply() // Tracks the swipe in the LinkedOut offline cache immediately
                            } label: {
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                    Text("Open Application & Auto-Copy Pitch")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        Button {
                            onApply()
                        } label: {
                            Text("Mark as Applied")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if auth.isAuthenticated, auth.profile?.personId != "dev-user" {
                            Button {
                                isShowingShareSheet = true
                            } label: {
                                Label("Post to LinkedIn", systemImage: "paperplane.circle.fill")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        LinearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        Button {
                            onCancel()
                        } label: {
                            Text("Not Yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Review Before Applying")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fullScreenCover(item: $safariWrapper) { wrapper in
                SafariView(url: wrapper.url)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheetView(job: job)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

struct URLWrapper: Identifiable {
    let id = UUID()
    let url: URL
}
