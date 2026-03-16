//
//  OnboardingOverlay.swift
//  LinkedOut
//
//  First-launch walkthrough — explains swipe gestures, scores, and flow.
//

import SwiftUI

struct OnboardingOverlay: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        ("hand.draw", "Swipe to Decide",
         "Swipe right to apply, left to pass, up to save for later. It's that simple.",
         .blue),
        ("brain.head.profile", "AI Scores Every Job",
         "Each job gets a Builder Score based on your skills, preferences, and the role requirements.",
         .purple),
        ("doc.text.magnifyingglass", "Auto Cover Letters",
         "A personalized cover letter is drafted for every job. Review it before you apply.",
         .green),
        ("slider.horizontal.3", "Tune Your Preferences",
         "Head to Settings to set your preferred roles, salary floor, and scoring weights.",
         .orange),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack(spacing: 24) {
                            Image(systemName: page.icon)
                                .font(.system(size: 64))
                                .foregroundStyle(page.color)
                                .symbolEffect(.pulse, options: .repeating)

                            Text(page.title)
                                .font(.title.bold())
                                .foregroundStyle(.white)

                            Text(page.subtitle)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 320)

                Spacer()

                // Action button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        isPresented = false
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(pages[currentPage].color)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)

                if currentPage < pages.count - 1 {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 12)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
    }
}
