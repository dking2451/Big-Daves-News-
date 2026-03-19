import Foundation

enum DateParsing {
    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let meridiemTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func combine(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateParts = calendar.dateComponents([.year, .month, .day], from: date)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = dateParts.year
        merged.month = dateParts.month
        merged.day = dateParts.day
        merged.hour = timeParts.hour
        merged.minute = timeParts.minute
        return calendar.date(from: merged) ?? date
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return isoDateFormatter.date(from: text)
    }

    static func parseTime(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let twentyFourHour = shortTimeFormatter.date(from: text) {
            return twentyFourHour
        }
        return meridiemTimeFormatter.date(from: text.uppercased())
    }
}
