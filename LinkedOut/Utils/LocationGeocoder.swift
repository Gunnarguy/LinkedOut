//
//  LocationGeocoder.swift
//  LinkedOut
//
//  Geocode job location strings → coordinates for the map. Uses Apple CLGeocoder
//  with a local cache so we don't re-geocode the same city repeatedly.
//

import CoreLocation
import Foundation
import Combine

@MainActor
final class LocationGeocoder: ObservableObject {
    struct GeoResult: Identifiable {
        let id: String          // job id
        let job: JobPayload
        let coordinate: CLLocationCoordinate2D
        let isRemoteHQ: Bool     // true = remote job, pin is company HQ
    }

    @Published var pins: [GeoResult] = []
    @Published var isGeocoding = false

    // cache: "San Francisco, CA" → coordinate
    private var cache: [String: CLLocationCoordinate2D] = [:]
    private let geocoder = CLGeocoder()

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

            // Geocode (rate-limited by Apple — 1 request at a time)
            do {
                let placemarks = try await geocoder.geocodeAddressString(locationToGeocode)
                if let coord = placemarks.first?.location?.coordinate {
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

        pins = results
    }
}
