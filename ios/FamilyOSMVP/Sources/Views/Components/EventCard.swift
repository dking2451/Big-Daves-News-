import SwiftUI

struct EventCard: View {
    let event: FamilyEvent

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
                Label(event.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
