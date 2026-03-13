//
//  JobMapView.swift
//  LinkedOut
//
//  Map tab — shows job opportunities plotted geographically.
//  Remote jobs show their company HQ with a wifi indicator.
//

import MapKit
import SwiftUI

struct JobMapView: View {
    @EnvironmentObject var jobs: JobsViewModel
    @StateObject private var geocoder = LocationGeocoder()
    @State private var selectedPin: LocationGeocoder.GeoResult?
    @State private var selectedJob: JobPayload?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showLegend = true

    /// All jobs across pending + saved + applied
    private var allJobs: [JobPayload] {
        var seen = Set<String>()
        var result: [JobPayload] = []
        for job in jobs.pendingJobs + jobs.savedJobs + jobs.appliedJobs {
            if seen.insert(job.id).inserted {
                result.append(job)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $cameraPosition, selection: $selectedPin) {
                    ForEach(geocoder.pins) { pin in
                        Annotation(pin.job.companyName, coordinate: pin.coordinate) {
                            JobMapPin(
                                score: pin.job.builderScore,
                                isRemote: pin.isRemoteHQ
                            )
                        }
                        .tag(pin)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }

                // Legend overlay
                if showLegend && !geocoder.pins.isEmpty {
                    legendView
                        .padding(12)
                        .transition(.opacity)
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation { showLegend.toggle() }
                        } label: {
                            Image(systemName: "info.circle")
                        }

                        if geocoder.isGeocoding {
                            ProgressView()
                        } else {
                            Text("\(geocoder.pins.count) pins")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .task {
                await geocoder.geocode(jobs: allJobs)
            }
            .onChange(of: allJobs.count) { _, _ in
                Task { await geocoder.geocode(jobs: allJobs) }
            }
            .onChange(of: selectedPin) { _, newPin in
                if let pin = newPin {
                    selectedJob = pin.job
                }
            }
            .sheet(item: $selectedJob) { job in
                JobDetailView(job: job)
            }
        }
    }

    // MARK: - Legend

    private var legendView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                Text("On-site / Hybrid")
                    .font(.caption2)
            }
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                    Image(systemName: "wifi")
                        .font(.system(size: 5))
                        .foregroundStyle(.white)
                }
                Text("Remote (HQ location)")
                    .font(.caption2)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Custom Map Pin

struct JobMapPin: View {
    let score: Double
    let isRemote: Bool

    private var pinColor: Color {
        if isRemote { return .blue }
        return score >= 0.70 ? .green : score >= 0.50 ? .orange : .red
    }

    var body: some View {
        ZStack {
            // Pin body
            Circle()
                .fill(pinColor)
                .frame(width: 30, height: 30)
                .shadow(color: pinColor.opacity(0.4), radius: 4, y: 2)

            if isRemote {
                // WiFi icon to indicate this is a remote job's HQ
                Image(systemName: "wifi")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                // Score number
                Text("\(Int(score * 100))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Make GeoResult selectable in Map

extension LocationGeocoder.GeoResult: Hashable {
    static func == (lhs: LocationGeocoder.GeoResult, rhs: LocationGeocoder.GeoResult) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
