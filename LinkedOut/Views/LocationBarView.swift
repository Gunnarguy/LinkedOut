//
//  LocationBarView.swift
//  LinkedOut
//
//  Horizontal scrollable location pills — filter the Discover tab by location.
//

import SwiftUI

// MARK: - Location Tab Model

struct LocationTab: Identifiable {
    let id: String
    let label: String
    let icon: String
    let count: Int
    let tint: Color
}

// MARK: - Location Bar

struct LocationBarView: View {
    let tabs: [LocationTab]
    @Binding var selectedTab: String
    let onManage: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    LocationPill(tab: tab, isSelected: selectedTab == tab.id) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTab = tab.id
                        }
                    }
                }

                // Manage locations button
                Button(action: onManage) {
                    Image(systemName: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.gray.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

// MARK: - Location Pill

private struct LocationPill: View {
    let tab: LocationTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(tab.label)
                    .font(.caption.weight(.medium))
                Text("\(tab.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? tab.tint : .gray.opacity(0.12))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
