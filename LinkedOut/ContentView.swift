//
//  ContentView.swift
//  LinkedOut
//
//  Created by Gunnar Hostetler on 3/9/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: auth.isAuthenticated)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(JobsViewModel())
}
