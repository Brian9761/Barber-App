import Foundation

/// Formats appointment lengths the way the booking menu shows them.
public enum DurationText {
    /// "15 min", "1 hr", "1 hr 15 min".
    public static func short(minutes: Int) -> String {
        precondition(minutes > 0, "A duration must be positive")
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, _): return "\(remainder) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(remainder) min"
        }
    }

    /// Spelled out for VoiceOver: "45 minutes", "1 hour 15 minutes".
    public static func spoken(minutes: Int) -> String {
        precondition(minutes > 0, "A duration must be positive")
        let hours = minutes / 60
        let remainder = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if remainder > 0 { parts.append(remainder == 1 ? "1 minute" : "\(remainder) minutes") }
        return parts.joined(separator: " ")
    }

    /// Summarizes several lengths: "45 min", "30–45 min", "45 min – 1 hr".
    public static func range(minutes: [Int]) -> String {
        guard let shortest = minutes.min(), let longest = minutes.max() else { return "" }
        if shortest == longest { return short(minutes: shortest) }
        if longest < 60 { return "\(shortest)–\(longest) min" }
        return short(minutes: shortest) + " – " + short(minutes: longest)
    }
}
