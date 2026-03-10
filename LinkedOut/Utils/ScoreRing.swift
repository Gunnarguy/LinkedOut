//
//  ScoreRing.swift
//  LinkedOut
//
//  Circular progress ring for builder_score display.
//

import SwiftUI

struct ScoreRing: View {
    let score: Double
    var size: CGFloat = 60
    var lineWidth: CGFloat = 6

    private var color: Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: score)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: score)

            Text("\(Int(score * 100))")
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 20) {
        ScoreRing(score: 0.95)
        ScoreRing(score: 0.72)
        ScoreRing(score: 0.45)
        ScoreRing(score: 0.2)
    }
    .padding()
}
