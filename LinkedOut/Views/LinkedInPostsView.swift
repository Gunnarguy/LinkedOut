//
//  LinkedInPostsView.swift
//  LinkedOut
//

import SwiftUI

struct LinkedInPostsView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var jobs: JobsViewModel

    private var canUseLinkedIn: Bool {
        auth.profile?.personId != nil && auth.profile?.personId != "dev-user" && !auth.needsReauth
    }

    var body: some View {
        Group {
            if auth.needsReauth {
                reconnectState
            } else if jobs.isSocialLoading && jobs.linkedInPosts.isEmpty {
                ProgressView("Fetching Posts...")
            } else if let error = jobs.socialError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text("Error Loading Posts")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task {
                            if let personId = auth.profile?.personId {
                                await jobs.fetchOwnPosts(personId: personId)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if jobs.linkedInPosts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Posts Found")
                        .font(.headline)
                    Text("You haven't posted anything on LinkedIn recently.")
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(jobs.linkedInPosts) { post in
                        NavigationLink(destination: LinkedInPostDetailView(post: post)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(post.text)
                                    .lineLimit(3)
                                    .font(.body)

                                HStack {
                                    Text(post.createdAt, style: .date)
                                    Text("•")
                                    Text(post.lifecycleState)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    if let personId = auth.profile?.personId {
                                        await jobs.deletePost(personId: personId, postUrn: post.urn)
                                    }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .refreshable {
                    if let personId = auth.profile?.personId, canUseLinkedIn {
                        await jobs.fetchOwnPosts(personId: personId)
                    }
                }
            }
        }
        .navigationTitle("My Posts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canUseLinkedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let personId = auth.profile?.personId {
                                await jobs.fetchOwnPosts(personId: personId)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            if jobs.linkedInPosts.isEmpty && canUseLinkedIn {
                Task {
                    if let personId = auth.profile?.personId {
                        await jobs.fetchOwnPosts(personId: personId)
                    }
                }
            }
        }
    }

    private var reconnectState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Reconnect LinkedIn")
                .font(.headline)
            Text("Your cached profile is still here, but LinkedIn API calls need a fresh session before you can manage posts.")
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
