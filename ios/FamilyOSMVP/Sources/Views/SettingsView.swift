import SwiftUI

struct SettingsView: View {
    private static let localSimulatorURL = "http://127.0.0.1:8000"
    private static let renderURL = "https://family-os-mvp-api.onrender.com"

    @EnvironmentObject private var store: EventStore
    @AppStorage("backendURL") private var backendURL = SettingsView.localSimulatorURL
    @State private var showExtractionSandbox = false
    @State private var connectionResult: String?
    @State private var isTestingConnection = false
    @State private var showingClearConfirm = false
    @State private var showingLoadDemoConfirm = false

    var body: some View {
        Form {
            Section("Backend") {
                TextField("Backend URL", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit {
                        backendURL = sanitizeBackendURL(backendURL)
                    }

                if shouldWarnLocalHTTPS(backendURL) {
                    Text("Local IPs should use http:// (not https://) for your dev server.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Text("Simulator: \(SettingsView.localSimulatorURL)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Physical iPhone: use your Mac LAN IP, e.g. http://192.168.1.23:8000")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Use Localhost") {
                        backendURL = SettingsView.localSimulatorURL
                    }
                    .buttonStyle(.bordered)

                    Button("Use Render") {
                        backendURL = SettingsView.renderURL
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    backendURL = sanitizeBackendURL(backendURL)
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
                .accessibilityLabel("Backend connection test")

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

            Section("User Profile") {
                NavigationLink("Manage Children") {
                    ManageChildrenView()
                }
            }

            #if DEBUG
            Section("Developer") {
                Button("Open Extraction Review Sandbox") {
                    showExtractionSandbox = true
                }
            }
            #endif

            Section("Data") {
                Button {
                    showingLoadDemoConfirm = true
                } label: {
                    Text("Load Demo Events")
                }

                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Text("Clear Local Data")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(isPresented: $showExtractionSandbox) {
            ReviewExtractedEventsView(candidates: sampleCandidates)
        }
        .alert("Clear all local events?", isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive) {
                store.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all events saved on this device.")
        }
        .alert("Load demo events?", isPresented: $showingLoadDemoConfirm) {
            Button("Load") {
                store.loadDemoEvents()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds sample events for testing recurring patterns, filters, and integrations.")
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

    private func sanitizeBackendURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localHost = convertedLocalHTTPSURL(trimmed) {
            return localHost
        }
        return trimmed
    }

    private func shouldWarnLocalHTTPS(_ raw: String) -> Bool {
        convertedLocalHTTPSURL(raw.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func convertedLocalHTTPSURL(_ urlString: String) -> String? {
        guard
            let url = URL(string: urlString),
            let host = url.host?.lowercased(),
            url.scheme?.lowercased() == "https",
            host == "localhost" || host == "127.0.0.1" || isLocalIPv4(host)
        else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "http"
        return components?.url?.absoluteString
    }

    private func isLocalIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        let nums = parts.compactMap { Int($0) }
        guard nums.count == 4 else { return false }
        return nums[0] == 10 || (nums[0] == 192 && nums[1] == 168) || (nums[0] == 172 && (16...31).contains(nums[1]))
    }
}

struct ManageChildrenView: View {
    @EnvironmentObject private var store: EventStore
    @State private var newChildName = ""
    @State private var renameSource: String?
    @State private var renameText = ""
    @State private var showingRenamePrompt = false

    var body: some View {
        List {
            Section("Add Child") {
                TextField("Child name", text: $newChildName)
                Button("Add") {
                    addChild()
                }
                .disabled(newChildName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Children") {
                let names = store.childNameList()
                if names.isEmpty {
                    ContentUnavailableView(
                        "No children yet",
                        systemImage: "person.2",
                        description: Text("Add names here or create events to auto-learn them.")
                    )
                } else {
                    ForEach(names, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Rename") {
                                renameSource = name
                                renameText = name
                                showingRenamePrompt = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .onDelete(perform: deleteChildren)
                }
            }
        }
        .navigationTitle("Manage Children")
        .alert("Rename Child", isPresented: $showingRenamePrompt) {
            TextField("New name", text: $renameText)
            Button("Save") {
                guard let renameSource else { return }
                store.renameChildName(from: renameSource, to: renameText)
                self.renameSource = nil
            }
            Button("Cancel", role: .cancel) {
                renameSource = nil
            }
        } message: {
            Text("Updating a child name also updates existing events for that child.")
        }
    }

    private func addChild() {
        store.addChildName(newChildName)
        newChildName = ""
    }

    private func deleteChildren(at offsets: IndexSet) {
        let names = store.childNameList()
        for index in offsets {
            guard names.indices.contains(index) else { continue }
            store.removeChildName(names[index])
        }
    }
}
