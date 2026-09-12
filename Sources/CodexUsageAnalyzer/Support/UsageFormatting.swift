import Foundation

enum UsageFormatting {
    static func integer(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func decimal(_ value: Double, digits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }

    static func compact(_ value: Int) -> String {
        let magnitude = abs(value)
        for (divisor, suffix) in [(1_000_000_000, " Mrd."), (1_000_000, " Mio."), (1_000, " Tsd.")] {
            guard magnitude >= divisor else { continue }
            let number = Double(value) / Double(divisor)
            let digits = number >= 100 ? 0 : 1
            return decimal(number, digits: digits) + suffix
        }
        return integer(value)
    }

    static func localDate(_ value: Date, includeTime: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = includeTime ? "dd.MM.yyyy, HH:mm" : "dd.MM.yyyy"
        return formatter.string(from: value)
    }

    static func duration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 { return "\(hours) h \(String(format: "%02d", minutes)) min" }
        if minutes > 0 { return "\(minutes) min \(String(format: "%02d", remainder)) s" }
        return "\(remainder) s"
    }
}
