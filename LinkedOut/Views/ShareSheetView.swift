import SwiftUI
import PhotosUI

struct ShareSheetView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    let job: JobPayload

    @State private var customText: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil

    @State private var isSharing = false
    @State private var shareSuccess: Bool? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                // Background glass effect
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header info
                        VStack(spacing: 8) {
                            Text("Share to LinkedIn")
                                .font(.title2.weight(.bold))

                            Text(job.roleTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(job.companyName)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 20)

                        // Text input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Thoughts")
                                .font(.headline)

                            TextEditor(text: $customText)
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(Color(uiColor: .systemBackground).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        }

                        // Image Picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Featured Image")
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
                                        Text("Select Image (Optional)")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 120)
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

                        // Status & Error
                        if isSharing {
                            ProgressView("Posting to LinkedIn...")
                                .padding()
                        } else if let success = shareSuccess {
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
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await sharePost() }
                    }
                    .bold()
                    .disabled(isSharing || customText.isEmpty)
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            self.selectedImageData = data
                        }
                    }
                }
            }
            .onAppear {
                // Pre-populate with drafting copy if desired
                if customText.isEmpty {
                    customText = "Check out this great opportunity at \(job.companyName) for a \(job.roleTitle)! #hiring"
                }
            }
        }
    }

    private func sharePost() async {
        guard let personId = authVM.profile?.personId else {
            errorMessage = "Not logged into LinkedIn."
            shareSuccess = false
            return
        }

        isSharing = true
        errorMessage = nil
        shareSuccess = nil

        do {
            if let imageData = selectedImageData {
                // Post with Media
                _ = try await APIClient.shared.shareToLinkedInWithMedia(
                    personId: personId,
                    customText: customText,
                    articleUrl: job.sourceUrl,
                    imageData: imageData
                )
            } else {
                // Just regular text + article URL (Standard Share)
                // Use the existing share method
                _ = try await APIClient.shared.shareToLinkedIn(
                    personId: personId,
                    jobId: job.id,
                    text: customText
                )
            }

            shareSuccess = true

            // Auto dismiss after a brief delay
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
            shareSuccess = false
        }

        isSharing = false
    }
}
