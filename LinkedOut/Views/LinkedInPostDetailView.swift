//
//  LinkedInPostDetailView.swift
//  LinkedOut
//

import SwiftUI

struct LinkedInPostDetailView: View {
    let post: LinkedInPost

    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var jobs: JobsViewModel

    @State private var newCommentText = ""
    @State private var isSubmitting = false

    var comments: [LinkedInComment] {
        jobs.linkedInComments[post.urn] ?? []
    }

    var reactions: [LinkedInReaction] {
        jobs.linkedInReactions[post.urn] ?? []
    }

    var hasLiked: Bool {
        guard let personUrn = auth.profile?.personId else { return false }
        return reactions.contains { $0.actor.contains(personUrn) || personUrn.contains($0.actor) }
    }

    private var canUseLinkedIn: Bool {
        auth.profile?.personId != nil && !auth.needsReauth
    }

    var body: some View {
        Group {
            if auth.needsReauth {
                reconnectState
            } else {
                ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Post content
                VStack(alignment: .leading, spacing: 12) {
                    Text(post.text)
                        .font(.body)

                    HStack {
                        Text(post.createdAt, style: .date)
                        Text("•")
                        Text(post.lifecycleState)
                        Spacer()

                        Button {
                            toggleLike()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hasLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                Text("\(reactions.count)")
                            }
                            .foregroundColor(hasLiked ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Comments Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Comments (\(comments.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    HStack {
                        TextField("Add a comment...", text: $newCommentText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button("Post") {
                            submitComment()
                        }
                        .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    }
                    .padding(.horizontal)

                    if let socialError = jobs.socialError {
                        Text(socialError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    if comments.isEmpty {
                        Text("No comments yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(commentDisplayName(comment))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(comment.createdAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Text(comment.text)
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                            .background(Color(.systemBackground))
                            .contextMenu {
                                // Only allow delete if we wrote it, but for our own posts we might have moderation rights.
                                // For simplicity, offer delete everywhere for now and let the API reject if unauthorized.
                                Button(role: .destructive) {
                                    deleteComment(commentId: comment.urn)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            Divider()
                        }
                    }
                }
            }
            .padding(.vertical)
        }
            }
        }
        .navigationTitle("Post Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let personId = auth.profile?.personId, canUseLinkedIn {
                Task {
                    await jobs.fetchComments(personId: personId, postUrn: post.urn)
                    await jobs.fetchReactions(personId: personId, postUrn: post.urn)
                }
            }
        }
    }

    private func toggleLike() {
        guard let personId = auth.profile?.personId else { return }
        Task {
            await jobs.toggleReaction(personId: personId, postUrn: post.urn, isAdding: !hasLiked)
        }
    }

    private func submitComment() {
        guard let personId = auth.profile?.personId else { return }
        let text = newCommentText
        newCommentText = ""
        isSubmitting = true
        Task {
            await jobs.addComment(personId: personId, postUrn: post.urn, text: text)
            isSubmitting = false
        }
    }

    private func deleteComment(commentId: String) {
        guard let personId = auth.profile?.personId else { return }
        Task {
            await jobs.deleteComment(personId: personId, postUrn: post.urn, commentId: commentId)
        }
    }

    private func commentDisplayName(_ comment: LinkedInComment) -> String {
        guard let personId = auth.profile?.personId else { return "Member" }
        if comment.actor.contains(personId) || personId.contains(comment.actor) {
            return "You"
        }
        return "Member"
    }

    private var reconnectState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Reconnect LinkedIn")
                .font(.headline)
            Text("Open the You tab and reconnect LinkedIn to view comments and reactions for your posts.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                Task { await auth.signInWithLinkedIn() }
            } label: {
                Label("Reconnect LinkedIn", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
