import CoreLocation
import Foundation
import MapKit

struct LocationValidationResult {
    let isValid: Bool
    let message: String
}

enum LocationValidationService {
    static func validateLocation(_ rawLocation: String) async -> LocationValidationResult {
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !location.isEmpty else {
            return LocationValidationResult(isValid: true, message: "No location provided.")
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = location
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let first = response.mapItems.first {
                let resolved = first.name ?? first.placemark.title ?? location
                return LocationValidationResult(
                    isValid: true,
                    message: "Validated: \(resolved)"
                )
            }
            return LocationValidationResult(
                isValid: false,
                message: "Couldn't verify this location. Check spelling or add more detail."
            )
        } catch {
            // Soft-fail on network/search issues to avoid blocking entry.
            return LocationValidationResult(
                isValid: false,
                message: "Location verification unavailable right now. You can still save."
            )
        }
    }
}

// MARK: - Resolve flyer / OCR text → Maps-friendly address + coordinates

enum LocationResolutionService {
    struct ResolvedPlace: Equatable {
        /// Single-line string suitable for display and `daddr` fallback.
        let formattedAddress: String
        let latitude: Double
        let longitude: Double
    }

    /// Best MapKit match for navigation; returns nil if search fails or coordinate is invalid.
    static func resolve(query raw: String) async -> ResolvedPlace? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return nil }
            return resolvedPlace(from: item)
        } catch {
            return nil
        }
    }

    static func formattedAddress(for mapItem: MKMapItem) -> String {
        let placemark = mapItem.placemark
        var segments: [String] = []

        if let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            segments.append(name)
        }

        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !street.isEmpty {
            segments.append(street)
        }

        let cityParts = [placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cityParts.isEmpty {
            segments.append(cityParts.joined(separator: ", "))
        }

        if segments.isEmpty, let title = placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        return segments.joined(separator: ", ")
    }

    static func resolvedPlace(from mapItem: MKMapItem) -> ResolvedPlace? {
        let formatted = formattedAddress(for: mapItem)
        guard !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let c = mapItem.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(c) else { return nil }
        return ResolvedPlace(formattedAddress: formatted, latitude: c.latitude, longitude: c.longitude)
    }
}
