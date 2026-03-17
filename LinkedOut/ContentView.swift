//
//  ContentView.swift
//  LinkedOut
//
//  Created by Gunnar Hostetler on 3/9/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: auth.isAuthenticated)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingOverlay(isPresented: $showOnboarding)
        }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            print("[APP] 🔀 Auth state changed: isAuthenticated=\(isAuth), needsReauth=\(auth.needsReauth), showing=\(isAuth ? "MainTabView" : "LoginView")")
            if isAuth && !hasSeenOnboarding {
                showOnboarding = true
                hasSeenOnboarding = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(JobsViewModel())
}
