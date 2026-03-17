//
//  LinkedOutApp.swift
//  LinkedOut
//
//  Created by Gunnar Hostetler on 3/9/26.
//

import SwiftUI

@main
struct LinkedOutApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var jobs = JobsViewModel()

    init() {
        print("[APP] 🚀 LinkedOut launching...")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(jobs)
        }
    }
}
