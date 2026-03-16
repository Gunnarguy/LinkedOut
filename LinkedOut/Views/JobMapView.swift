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
    @State private var previewJob: JobPayload?
    @State private var detailJob: JobPayload?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showLegend = true

    enum MapFilter: String, CaseIterable {
        case all = "All"
        case remote = "Remote"
        case onsite = "On-site"
    }
    @State private var mapFilter: MapFilter = .all

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

    /// Filtered pins based on the remote/onsite toggle
    private var filteredPins: [LocationGeocoder.GeoResult] {
        switch mapFilter {
        case .all: return geocoder.pins
        case .remote: return geocoder.pins.filter { $0.isRemoteHQ }
        case .onsite: return geocoder.pins.filter { !$0.isRemoteHQ }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $cameraPosition, selection: $selectedPin) {
                    ForEach(filteredPins) { pin in
                        Annotation(pin.job.companyName, coordinate: pin.coordinate) {
                            JobMapPin(
                                score: pin.job.builderScore,
                                isRemote: pin.isRemoteHQ,
                                groupCount: pin.locationGroup
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
            .safeAreaInset(edge: .top) {
                // Remote / On-site filter picker
                Picker("Filter", selection: $mapFilter) {
                    ForEach(MapFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
            .safeAreaInset(edge: .bottom) {
                // Pin preview card
                if let job = previewJob {
                    pinPreviewCard(job: job)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                            Text("\(filteredPins.count) pins")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .task {
                await geocoder.geocode(jobs: allJobs)
            }
            .onChange(of: allJobs.map(\.id)) { _, _ in
                Task { await geocoder.geocode(jobs: allJobs) }
            }
            .onChange(of: selectedPin) { _, newPin in
                withAnimation(.easeInOut(duration: 0.25)) {
                    previewJob = newPin?.job
                }
            }
            .sheet(item: $detailJob) { job in
                JobDetailView(job: job)
            }
        }
    }

    // MARK: - Pin Preview Card

    private func pinPreviewCard(job: JobPayload) -> some View {
        HStack(spacing: 12) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: job.builderScore)
                    .stroke(job.builderScore >= 0.7 ? .green : job.builderScore >= 0.5 ? .orange : .red,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(job.builderScore * 100))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.roleTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(job.companyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !job.location.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: job.isRemote ? "wifi" : "mappin")
                            .font(.system(size: 9))
                        Text(job.location)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                detailJob = job
            } label: {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            Button {
                withAnimation { previewJob = nil; selectedPin = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .padding(.horizontal)
        .padding(.bottom, 4)
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
            HStack(spacing: 6) {
                Circle()
                    .fill(.orange)
                    .frame(width: 10, height: 10)
                Text("Score 50-69")
                    .font(.caption2)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text("Score < 50")
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
    var groupCount: Int = 1

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
        .overlay(alignment: .topTrailing) {
            if groupCount > 1 {
                Text("\(groupCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(.secondary))
                    .offset(x: 6, y: -6)
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
