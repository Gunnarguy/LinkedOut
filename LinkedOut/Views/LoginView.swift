//
//  LoginView.swift
//  LinkedOut
//
//  LinkedIn sign-in screen.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var backendReachable: Bool?
    @State private var discovering = true
    @AppStorage("serverURL") private var serverURL: String = "http://Gunnars-Brain-Extension.local:8443"

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo & branding
            VStack(spacing: 16) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)

                Text("LinkedOut")
                    .font(.system(size: 42, weight: .black, design: .rounded))

                Text("AI-Powered Job Screening")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Value props
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "brain.head.profile",
                           title: "AI Bouncer",
                           subtitle: "Filters jobs that don't meet your bar")
                featureRow(icon: "hand.draw",
                           title: "Swipe to Decide",
                           subtitle: "Right = Apply, Left = Pass, Up = Save")
                featureRow(icon: "doc.text.magnifyingglass",
                           title: "Auto Cover Letters",
                           subtitle: "Personalized pitch for every role")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Backend status
            HStack(spacing: 6) {
                if discovering {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Searching for backend...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let reachable = backendReachable {
                    Circle()
                        .fill(reachable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(reachable ? "Backend connected" : "Backend offline — check server")
                        .font(.caption)
                        .foregroundColor(reachable ? .secondary : .red)
                }
            }
            .padding(.bottom, 8)

            // Error banner
            if let error = auth.error {
                ErrorBanner(message: error) {
                    auth.error = nil
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            // Actions
            VStack(spacing: 14) {
                Button {
                    Task { await auth.signInWithLinkedIn() }
                } label: {
                    HStack(spacing: 10) {
                        if auth.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "link")
                                .font(.title3)
                        }
                        Text(auth.isLoading ? "Connecting..." : "Sign in with LinkedIn")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(backendReachable == true ? .blue : .gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(auth.isLoading || backendReachable != true)

                Button {
                    auth.continueWithoutSignIn()
                } label: {
                    Text("Continue without sign-in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if backendReachable == false {
                    Button {
                        Task { await discoverAndCheck() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .task { await discoverAndCheck() }
        .sheet(isPresented: $auth.showOAuth) {
            if let url = auth.oauthURL {
                OAuthWebView(url: url) { code, state in
                    auth.showOAuth = false
                    Task { await auth.handleOAuthCallback(code: code, state: state) }
                } onCancel: {
                    auth.cancelOAuth()
                }
            }
        }
    }

    /// Auto-discover the backend, save the URL, and verify health.
    private func discoverAndCheck() async {
        discovering = true
        backendReachable = nil

        if let found = await ServerDiscovery.discover() {
            serverURL = found
            backendReachable = true
        } else {
            backendReachable = false
        }

        discovering = false
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
