import SwiftUI

struct EventCard: View {
    let event: FamilyEvent
    var onGetDirections: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.title)
                    .font(.headline)
                Spacer()

                HStack(spacing: 6) {
                    if event.recurrenceRule != .none {
                        iconBadge(
                            systemName: "repeat",
                            fill: .indigo,
                            accessibilityLabel: event.recurrenceRule.displayName
                        )
                    }

                    iconBadge(
                        systemName: categoryIconName,
                        fill: categoryBadgeColor,
                        accessibilityLabel: event.category.displayName
                    )
                }
            }

            Text(event.childName.isEmpty ? "Family" : event.childName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(event.startDateTime.formatted(date: .abbreviated, time: .shortened)) - \(event.endDateTime.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)

            if !event.location.isEmpty {
                HStack(spacing: 8) {
                    if let onGetDirections {
                        Button {
                            onGetDirections()
                        } label: {
                            Label(event.location, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Get directions to \(event.location)")
                        .help("Open location in Maps")
                    } else {
                        Label(event.location, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if let onGetDirections {
                        Button {
                            onGetDirections()
                        } label: {
                            Image(systemName: "location.north.line.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Get directions to \(event.location)")
                        .help("Get directions")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func iconBadge(systemName: String, fill: Color, accessibilityLabel: String) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(fill))
            .accessibilityLabel(accessibilityLabel)
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
}
