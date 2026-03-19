import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: EventStore
    @AppStorage("backendURL") private var backendURL = "https://family-os-mvp-api.onrender.com"
    @State private var showExtractionSandbox = false
    @State private var connectionResult: String?
    @State private var isTestingConnection = false

    var body: some View {
        Form {
            Section("Backend") {
                TextField("Backend URL", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button {
                    Task { await testConnection() }
                } label: {
                    if isTestingConnection {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Testing...")
                        }
                    } else {
                        Text("Backend connection test")
                    }
                }
                .disabled(isTestingConnection)

                if let connectionResult {
                    Text(connectionResult)
                        .font(.footnote)
                        .foregroundStyle(connectionResult.contains("Connected") ? .green : .red)
                }
            }

            Section("AI Disclaimer") {
                Text("AI extraction can be wrong or ambiguous. Always review before saving events.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Policy: if date is unclear, leave it blank. If time is unclear, ambiguity must be flagged. Never invent certainty.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section("Developer") {
                Button("Open Extraction Review Sandbox") {
                    showExtractionSandbox = true
                }
            }
            #endif

            Section("Data") {
                Button(role: .destructive) {
                    store.clearAll()
                } label: {
                    Text("Clear Local Data")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(isPresented: $showExtractionSandbox) {
            ReviewExtractedEventsView(candidates: sampleCandidates)
        }
    }

    private var sampleCandidates: [ExtractedEventCandidate] {
        [
            ExtractedEventCandidate(
                title: "PTA Meeting",
                childName: "",
                category: "school",
                date: nil,
                startTime: "18:00",
                endTime: "19:00",
                location: "Cafeteria",
                notes: "Date unclear in source text",
                confidence: 0.55,
                ambiguityFlag: true
            ),
            ExtractedEventCandidate(
                title: "Dentist Appointment",
                childName: "Mia",
                category: "medical",
                date: "2026-03-27",
                startTime: nil,
                endTime: nil,
                location: "Downtown Dental",
                notes: "Time not provided",
                confidence: 0.78,
                ambiguityFlag: true
            ),
        ]
    }

    private func testConnection() async {
        connectionResult = nil
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let ok = try await APIClient(baseURL: backendURL).healthCheck()
            connectionResult = ok ? "Connected to backend." : "Backend responded unexpectedly."
        } catch {
            connectionResult = "Connection failed: \(error.localizedDescription)"
        }
    }
}
