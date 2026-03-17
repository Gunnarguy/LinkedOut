//
//  ComposePostView.swift
//  LinkedOut
//
//  Standalone LinkedIn post composer — write whatever you want,
//  attach an optional image, and post directly to your feed.
//

import SwiftUI
import PhotosUI

struct ComposePostView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    @State private var postText: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var articleURL: String = ""

    @State private var isPosting = false
    @State private var postSuccess: Bool? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Text("New LinkedIn Post")
                                .font(.title2.weight(.bold))

                            Text("Share your thoughts with your network")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)

                        // Text input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What's on your mind?")
                                .font(.headline)

                            TextEditor(text: $postText)
                                .frame(minHeight: 160)
                                .padding(12)
                                .background(Color(uiColor: .systemBackground).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)

                            Text("\(postText.count) / 3,000")
                                .font(.caption2)
                                .foregroundStyle(postText.count > 3000 ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        // Optional link
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Link (Optional)")
                                .font(.headline)

                            TextField("https://...", text: $articleURL)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(12)
                                .background(Color(uiColor: .systemBackground).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }

                        // Image Picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Image (Optional)")
                                .font(.headline)

                            if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 200)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                                    Button {
                                        withAnimation {
                                            self.selectedImageData = nil
                                            self.selectedItem = nil
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .padding(8)
                                }
                            } else {
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    VStack(spacing: 12) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 32))
                                        Text("Select Image")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 100)
                                    .background(Color(uiColor: .systemBackground).opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                            .foregroundStyle(.secondary.opacity(0.5))
                                    )
                                }
                                .tint(.accentColor)
                            }
                        }

                        // Status
                        if isPosting {
                            ProgressView("Posting to LinkedIn...")
                                .padding()
                        } else if let success = postSuccess {
                            if success {
                                Label("Posted successfully!", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await submitPost() }
                    }
                    .bold()
                    .disabled(isPosting || postText.isEmpty || postText.count > 3000)
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run { self.selectedImageData = data }
                    }
                }
            }
        }
    }

    private func submitPost() async {
        guard let personId = authVM.profile?.personId else {
            errorMessage = "Not logged into LinkedIn."
            postSuccess = false
            return
        }

        isPosting = true
        errorMessage = nil
        postSuccess = nil

        do {
            let urlToShare = articleURL.trimmingCharacters(in: .whitespacesAndNewlines)

            if let imageData = selectedImageData {
                _ = try await APIClient.shared.shareToLinkedInWithMedia(
                    personId: personId,
                    customText: postText,
                    articleUrl: urlToShare,
                    imageData: imageData
                )
            } else {
                _ = try await APIClient.shared.postToLinkedIn(
                    personId: personId,
                    text: postText,
                    articleUrl: urlToShare.isEmpty ? nil : urlToShare
                )
            }

            postSuccess = true
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            postSuccess = false
        }

        isPosting = false
    }
}
