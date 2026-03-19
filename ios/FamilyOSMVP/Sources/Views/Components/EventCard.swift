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
                Text(event.category.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
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
                            Label("Directions", systemImage: "location.north.line")
                                .labelStyle(.iconOnly)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
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
}
