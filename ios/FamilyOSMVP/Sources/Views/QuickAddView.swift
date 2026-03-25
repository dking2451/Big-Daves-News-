import SwiftUI

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EventStore
    @FocusState private var titleFocused: Bool

    @State private var title = ""
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var startTime = QuickAddView.nextRoundedTimeSlot(from: Date())
    @State private var selectedChild = ""
    @State private var assignment: EventAssignment = .unassigned

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick Add") {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if canSave {
                                save()
                            }
                        }

                    DatePicker("Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                }

                Section("Assigned to (optional)") {
                    Picker("Assigned to", selection: $assignment) {
                        ForEach(EventAssignment.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if childOptions.isEmpty {
                    Section("Child") {
                        Text("No children yet. Add child names in Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Child (Optional)") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                childChip(title: "None", isSelected: selectedChild.isEmpty) {
                                    selectedChild = ""
                                }
                                ForEach(childOptions, id: \.self) { child in
                                    childChip(title: child, isSelected: selectedChild == child) {
                                        selectedChild = child
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .onAppear {
                titleFocused = true
            }
        }
    }

    private var childOptions: [String] {
        store.childNameList()
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedChild = selectedChild.trimmingCharacters(in: .whitespacesAndNewlines)
        let childDefaults = trimmedChild.isEmpty ? nil : store.childDefaults(for: trimmedChild)
        let category = childDefaults?.defaultCategory ?? .other
        let endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime

        let event = FamilyEvent(
            title: trimmedTitle,
            childName: trimmedChild,
            category: category,
            date: date,
            startTime: startTime,
            endTime: endTime,
            location: "",
            notes: "",
            sourceType: .manual,
            isApproved: true,
            assignment: assignment
        )
        store.addEvent(event)
        dismiss()
    }

    @ViewBuilder
    private func childChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private static func nextRoundedTimeSlot(from now: Date) -> Date {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now
    }
}
