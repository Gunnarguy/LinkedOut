//
//  LocationGeocoder.swift
//  LinkedOut
//
//  Geocode job location strings → coordinates for the map. Uses MapKit
//  MKGeocodingRequest with a local cache so we don't re-geocode the same city repeatedly.
//

import MapKit
import Foundation
import Combine

@MainActor
final class LocationGeocoder: ObservableObject {
    struct GeoResult: Identifiable {
        let id: String          // job id
        let job: JobPayload
        let coordinate: CLLocationCoordinate2D
        let isRemoteHQ: Bool     // true = remote job, pin is company HQ
        var locationGroup: Int = 1  // how many jobs share this location
    }

    @Published var pins: [GeoResult] = []
    @Published var isGeocoding = false

    // cache: "San Francisco, CA" → coordinate
    private var cache: [String: CLLocationCoordinate2D] = [:]

    /// Geocode a batch of jobs. Remote jobs get pinned to their HQ location
    /// (extracted from the location string) with a remote indicator.
    func geocode(jobs: [JobPayload]) async {
        isGeocoding = true
        defer { isGeocoding = false }

        var results: [GeoResult] = []

        for job in jobs {
            let rawLocation = job.location.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip fully unknown locations
            if rawLocation.isEmpty || rawLocation.lowercased() == "not specified" {
                continue
            }

            // Determine if remote — look for the location string to identify HQ
            let isRemote = job.isRemote
            let locationToGeocode: String

            if isRemote {
                // Try to extract a city from strings like "Remote (San Francisco, CA)"
                // or "Remote - New York" or just "San Francisco, CA"
                let cleaned = rawLocation
                    .replacingOccurrences(of: "Remote", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "remote-first", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Anywhere", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

                // If after stripping "Remote" there's still a city, geocode it
                if cleaned.count >= 3 {
                    locationToGeocode = cleaned
                } else {
                    continue  // Fully remote with no HQ — skip map pin
                }
            } else {
                locationToGeocode = rawLocation
            }

            // Check cache first
            if let cached = cache[locationToGeocode.lowercased()] {
                results.append(GeoResult(
                    id: job.id,
                    job: job,
                    coordinate: cached,
                    isRemoteHQ: isRemote
                ))
                continue
            }

            // Geocode via MapKit
            do {
                guard let request = MKGeocodingRequest(addressString: locationToGeocode) else {
                    continue
                }
                let mapItems = try await request.mapItems
                if let coord = mapItems.first?.location.coordinate {
                    cache[locationToGeocode.lowercased()] = coord
                    results.append(GeoResult(
                        id: job.id,
                        job: job,
                        coordinate: coord,
                        isRemoteHQ: isRemote
                    ))
                }
            } catch {
                // Geocoding failed — skip this pin silently
                continue
            }
        }

        applyJitter(&results)
        pins = results
    }

    /// Spread overlapping pins into a small circle so they're all visible and tappable.
    private func applyJitter(_ results: inout [GeoResult]) {
        // Group by rounded coordinate (same location)
        var groups: [String: [Int]] = [:]
        for (i, r) in results.enumerated() {
            let key = String(format: "%.4f,%.4f", r.coordinate.latitude, r.coordinate.longitude)
            groups[key, default: []].append(i)
        }

        for (_, indices) in groups where indices.count > 1 {
            let count = indices.count
            // Radius scales with count: ~200m base, up to ~500m for large groups
            let radius = 0.002 + 0.001 * min(Double(count), 8.0) / 8.0
            for (offset, idx) in indices.enumerated() {
                let angle = 2 * .pi * Double(offset) / Double(count)
                let orig = results[idx]
                let jittered = CLLocationCoordinate2D(
                    latitude: orig.coordinate.latitude + radius * cos(angle),
                    longitude: orig.coordinate.longitude + radius * sin(angle)
                )
                results[idx] = GeoResult(
                    id: orig.id,
                    job: orig.job,
                    coordinate: jittered,
                    isRemoteHQ: orig.isRemoteHQ,
                    locationGroup: count
                )
            }
        }
    }
}
