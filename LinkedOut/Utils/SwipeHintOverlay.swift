//
//  SwipeHintOverlay.swift
//  LinkedOut
//
//  Shows APPLY / REJECT / SAVE hints during card drag.
//

import SwiftUI

struct SwipeHintOverlay: View {
    let hint: JobsViewModel.SwipeHint

    var body: some View {
        Group {
            switch hint {
            case .apply:
                hintLabel("APPLY", icon: "checkmark.circle.fill", color: .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 30)
            case .reject:
                hintLabel("PASS", icon: "xmark.circle.fill", color: .red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 30)
            case .save:
                hintLabel("SAVE", icon: "bookmark.circle.fill", color: .blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 30)
            case .none:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hint != .none)
    }

    private func hintLabel(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.title.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(color, lineWidth: 2)
                    )
            )
    }
}
