import Foundation

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL."
        case .invalidResponse:
            return "Unexpected response from backend."
        case .serverError(let message):
            return message
        }
    }
}

struct APIClient {
    /// FastAPI often returns `{"detail":{"error":{"message":"..."}}}`; sometimes `detail` is a string.
    private static func parseFastAPIErrorMessage(from data: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let detail = raw["detail"] as? [String: Any],
           let error = detail["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        if let detail = raw["detail"] as? String {
            return detail
        }
        return nil
    }

    var baseURL: String
    private var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func healthCheck() async throws -> Bool {
        guard let url = URL(string: "\(normalizedBaseURL)/health") else {
            throw APIClientError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url, delegate: nil)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 404 {
                throw APIClientError.serverError(
                    "HTTP 404 on /health — this URL is not the Family OS API. In Render, deploy `backend/family-os-mvp-api`, then copy the Web Service HTTPS URL (base only, no path) into Settings."
                )
            }
            throw APIClientError.serverError("Health check failed (HTTP \(http.statusCode)).")
        }
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (parsed?["status"] as? String)?.lowercased() == "ok"
    }

    func extractEvents(ocrText: String, sourceHint: String?) async throws -> [ExtractedEventCandidate] {
        guard let url = URL(string: "\(normalizedBaseURL)/v1/extract-events") else {
            throw APIClientError.invalidURL
        }

        let payload = [
            "ocrText": ocrText,
            "sourceHint": sourceHint ?? "",
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if let message = Self.parseFastAPIErrorMessage(from: data) {
                throw APIClientError.serverError(message)
            }
            throw APIClientError.serverError("Extraction failed (\(http.statusCode)).")
        }

        let decoded = try JSONDecoder().decode(ExtractEventsResponse.self, from: data)
        return decoded.candidates
    }
}
