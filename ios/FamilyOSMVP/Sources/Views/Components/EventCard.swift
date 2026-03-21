import SwiftUI

struct EventCard: View {
    let event: FamilyEvent
    var showsConflictBadge: Bool = false
    var showsWarningBadge: Bool = false
    var combinedCount: Int = 1
    /// When set (e.g. cross-child family moment), shown instead of `event.childName`.
    var childNamesDisplayLine: String? = nil
    var childAccentColor: Color? = nil
    var onGetDirections: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(resolvedAccentColor.opacity(0.85))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title.isEmpty ? "Untitled Event" : event.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(eventTimeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            if showsChildLine {
                                Circle()
                                    .fill(resolvedAccentColor.opacity(0.85))
                                    .frame(width: 7, height: 7)
                            }
                            Text(resolvedChildLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }

                HStack(spacing: 6) {
                    if showsConflictBadge {
                        detailChip(
                            text: "Conflict",
                            systemName: "exclamationmark.triangle.fill",
                            tint: .orange
                        )
                    } else if showsWarningBadge {
                        detailChip(
                            text: "Tight Turn",
                            systemName: "clock.badge.exclamationmark",
                            tint: .yellow
                        )
                    }

                    if event.sourceType == .aiExtracted {
                        detailChip(
                            text: "Imported",
                            systemName: "wand.and.stars",
                            tint: .secondary
                        )
                    }

                    if event.recurrenceRule != .none {
                        detailChip(
                            text: event.recurrenceRule.displayName,
                            systemName: "repeat",
                            tint: .indigo
                        )
                    }

                    if event.assignment != .unassigned {
                        detailChip(
                            text: event.assignment.displayName,
                            systemName: event.assignment.chipIconSystemName,
                            tint: event.assignment.chipTint
                        )
                    }

                    detailChip(
                        text: event.category.displayName,
                        systemName: categoryIconName,
                        tint: categoryBadgeColor
                    )
                }

                if combinedCount > 1, childNamesDisplayLine == nil {
                    Text("Combined from \(combinedCount) similar entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()

                    HStack(spacing: 10) {
                        if let onGetDirections {
                            Button {
                                onGetDirections()
                            } label: {
                                Label(event.location, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Get directions to \(event.location)")
                            .help("Open location in Maps")
                        } else {
                            Label(event.location, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let onGetDirections {
                            Button {
                                onGetDirections()
                            } label: {
                                Image(systemName: "location.north.line.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.accentColor))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Get directions to \(event.location)")
                            .help("Get directions")
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(resolvedAccentColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailChip(text: String, systemName: String, tint: Color) -> some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    private var categoryIconName: String {
        switch event.category {
        case .school:
            return "graduationcap.fill"
        case .sports:
            return "figure.run"
        case .medical:
            return "cross.case.fill"
        case .social:
            return "person.2.fill"
        case .other:
            return "sparkles"
        }
    }

    private var categoryBadgeColor: Color {
        switch event.category {
        case .school:
            return .blue
        case .sports:
            return .green
        case .medical:
            return .red
        case .social:
            return .purple
        case .other:
            return .gray
        }
    }

    private var showsChildLine: Bool {
        if let line = childNamesDisplayLine, !line.isEmpty { return true }
        return !event.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedChildLine: String {
        if let line = childNamesDisplayLine, !line.isEmpty { return line }
        return event.childName.isEmpty ? "Family" : event.childName
    }

    private var resolvedAccentColor: Color {
        if let line = childNamesDisplayLine, !line.isEmpty {
            return childAccentColor ?? Color.accentColor
        }
        guard event.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .primary
        }
        return childAccentColor ?? .blue
    }

    private var eventTimeText: String {
        "\(event.startDateTime.formatted(date: .abbreviated, time: .shortened)) - \(event.endDateTime.formatted(date: .omitted, time: .shortened))"
    }
}
