//
//  ResumeView.swift
//  LinkedOut
//
//  LinkedIn profile card — connected identity from LinkedIn OAuth.
//

import SwiftUI

struct ResumeView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let profile = auth.profile {
                    heroHeader(profile)

                    // Connected status card
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("LinkedIn Connected")
                                    .font(.subheadline.weight(.semibold))
                                Text("Your profile powers the AI job scorer — no manual entry needed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.green.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: appeared)

                    Color.clear.frame(height: 40)
                } else {
                    emptyProfileState
                }
            }
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.indigo.opacity(0.05), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshProfile() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.trianglehead.2.counterclockwise")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.indigo)
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                appeared = true
            }
        }
        .alert("Refresh Failed", isPresented: .init(
            get: { refreshError != nil },
            set: { if !$0 { refreshError = nil } }
        )) {
            Button("OK") { refreshError = nil }
        } message: {
            Text(refreshError ?? "")
        }
    }

    // MARK: - Hero Header

    private func heroHeader(_ profile: LinkedInProfile) -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.7), .purple.opacity(0.5), .blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 300, height: 300)
                    .offset(x: 120, y: -80)
                    .blur(radius: 60)

                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .offset(x: -100, y: 20)
                    .blur(radius: 40)
            }
            .frame(height: 240)

            VStack(spacing: 0) {
                // Avatar
                Group {
                    if let picUrl = URL(string: profile.profilePictureUrl),
                       !profile.profilePictureUrl.isEmpty {
                        AsyncImage(url: picUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                initialsView(profile, size: 100)
                            }
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                    } else {
                        initialsView(profile, size: 100)
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .offset(y: appeared ? 0 : 30)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.75), value: appeared)

                Text(profile.fullName)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .padding(.top, 12)

                if !profile.headline.isEmpty {
                    Text(profile.headline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                }

                HStack(spacing: 10) {
                    if !profile.email.isEmpty {
                        chipButton(icon: "envelope.fill", text: profile.email, color: .white.opacity(0.2)) {
                            if let url = URL(string: "mailto:\(profile.email)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }

                    if let url = URL(string: profile.linkedInUrl), !profile.linkedInUrl.isEmpty {
                        chipButton(icon: "link", text: "LinkedIn", color: .white.opacity(0.2)) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.top, 12)

                if !profile.verifications.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(profile.verifications, id: \.self) { v in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                Text(v.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption2.weight(.medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.25), in: Capsule())
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    private func chipButton(icon: String, text: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(text)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
        }
    }

    private func initialsView(_ profile: LinkedInProfile, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Text(String(profile.firstName.prefix(1)) + String(profile.lastName.prefix(1)))
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var emptyProfileState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.indigo)

            Text("No Profile Yet")
                .font(.title2.bold())

            Text("Sign in with LinkedIn to connect your profile.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Actions

    private func refreshProfile() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await auth.fetchResume()
        if let err = auth.error {
            refreshError = err
            auth.error = nil
        }
    }
}
