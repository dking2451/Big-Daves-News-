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
    /// Subtle emphasis for events starting within the next ~24 hours (e.g. Upcoming timeline).
    var nearTermHighlight: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(resolvedAccentColor.opacity(0.85))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 14) {
                // Primary block: title, time, children (family-first hierarchy)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title.isEmpty ? "Untitled Event" : event.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)

                        Text(eventTimeText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        if showsChildLine {
                            Text(formattedChildrenLine)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.quaternary)
                        .padding(.top, 4)
                }

                // Chips: secondary metadata
                HStack(spacing: 5) {
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
                            text: event.recurrenceChipLabel,
                            systemName: "repeat",
                            tint: .indigo
                        )
                        .accessibilityLabel(event.recurrenceSummaryText)
                    }

                    if event.assignment != .unassigned {
                        detailChip(
                            text: event.assignment.rowLabel,
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .center, spacing: 10) {
                        if let onGetDirections {
                            Button {
                                onGetDirections()
                            } label: {
                                Label(event.location, systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Get directions to \(event.location)")
                            .help("Open location in Maps")
                        } else {
                            Label(event.location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }

                        if let onGetDirections {
                            Button {
                                onGetDirections()
                            } label: {
                                Image(systemName: "location.north.line.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(FamilyTheme.accent))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Get directions to \(event.location)")
                            .help("Get directions")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FamilyLayout.cardInnerCornerRadius, style: .continuous)
                .fill(nearTermHighlight ? Color(.tertiarySystemFill) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FamilyLayout.cardInnerCornerRadius, style: .continuous)
                .stroke(resolvedAccentColor.opacity(nearTermHighlight ? 0.26 : 0.18), lineWidth: nearTermHighlight ? 1.25 : 1)
        )
    }

    @ViewBuilder
    private func detailChip(text: String, systemName: String, tint: Color) -> some View {
        Label(text, systemImage: systemName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint.opacity(0.92))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.09))
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

    /// Single child, "Family", or cross-child line with middle dots (e.g. `Ava • Tim`).
    private var formattedChildrenLine: String {
        if let line = childNamesDisplayLine, !line.isEmpty {
            return line
                .replacingOccurrences(of: ", ", with: " • ")
        }
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
        "\(event.startDateTime.formatted(date: .abbreviated, time: .shortened)) – \(event.endDateTime.formatted(date: .omitted, time: .shortened))"
    }
}
