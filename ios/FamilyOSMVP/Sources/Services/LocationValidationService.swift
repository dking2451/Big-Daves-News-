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
