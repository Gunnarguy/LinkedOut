//
//  LocationManagerSheet.swift
//  LinkedOut
//
//  Manage preferred locations — add cities, remove, or pick from suggestions.
//

import SwiftUI

struct LocationManagerSheet: View {
    @Binding var locations: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var newCity = ""
    @State private var newState = ""

    // Popular cities — Michigan first, then other tech hubs
    private let suggestedCities: [(section: String, cities: [String])] = [
        ("Michigan", [
            "Ann Arbor, Michigan",
            "Detroit, Michigan",
            "Grand Rapids, Michigan",
            "Kalamazoo, Michigan",
            "Lansing, Michigan",
            "Troy, Michigan",
            "Traverse City, Michigan",
            "Holland, Michigan",
            "Battle Creek, Michigan",
            "Flint, Michigan",
        ]),
        ("Popular Tech Hubs", [
            "Austin, Texas",
            "Denver, Colorado",
            "Seattle, Washington",
            "Portland, Oregon",
            "Nashville, Tennessee",
            "Raleigh, North Carolina",
            "Salt Lake City, Utah",
            "Minneapolis, Minnesota",
            "Chicago, Illinois",
            "Boston, Massachusetts",
            "New York, New York",
            "San Francisco, California",
            "Los Angeles, California",
        ]),
    ]

    var body: some View {
        NavigationStack {
            List {
                // ── Current Locations ──
                Section {
                    if locations.isEmpty {
                        HStack {
                            Image(systemName: "mappin.slash")
                                .foregroundStyle(.secondary)
                            Text("No locations added")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(locations, id: \.self) { location in
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.blue)
                            Text(location)
                            Spacer()
                        }
                    }
                    .onDelete { locations.remove(atOffsets: $0) }
                } header: {
                    Text("Your Locations")
                } footer: {
                    Text("Jobs near these cities get their own tab in Discover. Swipe to remove.")
                }

                // ── Add Custom ──
                Section("Add Location") {
                    HStack(spacing: 6) {
                        TextField("City", text: $newCity)
                            .textInputAutocapitalization(.words)
                        Text(",")
                            .foregroundStyle(.secondary)
                        TextField("State", text: $newState)
                            .textInputAutocapitalization(.words)
                            .frame(width: 100)
                        Button(action: addCustomLocation) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newCity.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // ── Suggestions ──
                ForEach(suggestedCities, id: \.section) { group in
                    let unused = group.cities.filter { !locations.contains($0) }
                    if !unused.isEmpty {
                        Section(group.section) {
                            ForEach(unused, id: \.self) { city in
                                Button {
                                    withAnimation { locations.append(city) }
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(.blue)
                                        Text(city)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func addCustomLocation() {
        let city = newCity.trimmingCharacters(in: .whitespaces)
        let state = newState.trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { return }
        let entry = state.isEmpty ? city : "\(city), \(state)"
        if !locations.contains(entry) {
            withAnimation { locations.append(entry) }
        }
        newCity = ""
        newState = ""
    }
}
