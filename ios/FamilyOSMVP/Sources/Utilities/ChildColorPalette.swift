import SwiftUI

struct ChildColorPalette {
    struct Option: Identifiable {
        let token: String
        let name: String
        let color: Color

        var id: String { token }
    }

    static let options: [Option] = [
        Option(token: "blue", name: "Blue", color: .blue),
        Option(token: "green", name: "Green", color: .green),
        Option(token: "orange", name: "Orange", color: .orange),
        Option(token: "purple", name: "Purple", color: .purple),
        Option(token: "pink", name: "Pink", color: .pink),
        Option(token: "teal", name: "Teal", color: .teal),
        Option(token: "indigo", name: "Indigo", color: .indigo),
        Option(token: "red", name: "Red", color: .red),
    ]

    static func color(for token: String?) -> Color {
        guard let token else { return .blue }
        return options.first(where: { $0.token == token })?.color ?? .blue
    }
}
