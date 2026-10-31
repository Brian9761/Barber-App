import Foundation

/// An appointment as the app keeps it for reminders, and as the previous version of the app saved
/// bookings made on Squire (which the app reads once, to carry them over).
public struct Appointment: Codable, Hashable, Identifiable, Sendable {
    /// Shown as the barber when the client booked whoever is free first.
    public static let firstAvailableName = "First available"

    public let id: UUID
    public var serviceID: String
    public var serviceName: String
    /// The barber's ID, or `nil` for the first available barber.
    public var barberID: String?
    /// "Carlos", or "First available".
    public var barberName: String
    public var start: Date
    public var durationMinutes: Int
    /// The price as shown when booking, e.g. "$45" or "$35–$40".
    public var priceLabel: String
    public let createdAt: Date

    /// - Parameter barberName: Who it's with; `nil` means the first available barber.
    public init(
        id: UUID = UUID(),
        serviceID: String,
        serviceName: String,
        barberID: String?,
        barberName: String? = nil,
        start: Date,
        durationMinutes: Int,
        priceLabel: String,
        createdAt: Date = Date()
    ) {
        precondition(durationMinutes > 0, "An appointment needs a length")
        self.id = id
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.barberID = barberID
        self.barberName = barberName ?? Appointment.firstAvailableName
        self.start = start
        self.durationMinutes = durationMinutes
        self.priceLabel = priceLabel
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        guard durationMinutes > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .durationMinutes,
                in: container,
                debugDescription: "An appointment needs a length"
            )
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            serviceID: try container.decode(String.self, forKey: .serviceID),
            serviceName: try container.decode(String.self, forKey: .serviceName),
            barberID: try container.decodeIfPresent(String.self, forKey: .barberID),
            barberName: try container.decodeIfPresent(String.self, forKey: .barberName),
            start: try container.decode(Date.self, forKey: .start),
            durationMinutes: durationMinutes,
            priceLabel: try container.decode(String.self, forKey: .priceLabel),
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }

    public var end: Date {
        start.addingTimeInterval(TimeInterval(durationMinutes) * 60)
    }

    /// "45 min", "1 hr 15 min".
    public var durationLabel: String {
        DurationText.short(minutes: durationMinutes)
    }

    /// Hasn't finished yet: it's later, or happening right now.
    public func isUpcoming(at now: Date) -> Bool {
        end > now
    }
}

/// When to remind a client about an appointment.
public enum AppointmentReminderKind: String, CaseIterable, Sendable {
    /// 24 hours before it starts.
    case dayBefore
    /// An hour before it starts.
    case hourBefore

    /// How long before the start the reminder fires.
    public var leadTime: TimeInterval {
        switch self {
        case .dayBefore: return 24 * 60 * 60
        case .hourBefore: return 60 * 60
        }
    }
}

/// A notification to schedule for an appointment.
public struct AppointmentReminder: Hashable, Sendable {
    public let kind: AppointmentReminderKind
    public let date: Date
    /// "Haircut tomorrow at 2:30 PM".
    public let title: String
    /// "With Carlos at Izzy Clipz, 1919 Mission Ave."
    public let body: String
}

/// Sorting, cleanup, reminders and storage for saved appointments.
public enum AppointmentPlanner {
    /// Appointments that haven't ended yet, soonest first.
    public static func upcoming(_ appointments: [Appointment], now: Date) -> [Appointment] {
        sorted(appointments.filter { $0.isUpcoming(at: now) })
    }

    /// Drops appointments that ended more than `keepDays` ago; the rest are
    /// sorted by start.
    public static func pruned(_ appointments: [Appointment], now: Date, keepDays: Int = 30) -> [Appointment] {
        precondition(keepDays >= 0, "Can't keep a negative number of days")
        let cutoff = now.addingTimeInterval(-TimeInterval(keepDays) * 24 * 60 * 60)
        return sorted(appointments.filter { $0.end >= cutoff })
    }

    /// Start of the most recent appointment that has already ended, e.g. to
    /// count "weeks since your last cut" from.
    public static func latestFinishedStart(_ appointments: [Appointment], now: Date) -> Date? {
        appointments.filter { !$0.isUpcoming(at: now) }.map(\.start).max()
    }

    /// The day-before and hour-before reminders that are still in the future.
    ///
    /// Titles read "Haircut tomorrow at 2:30 PM" and "Haircut at 2:30 PM";
    /// bodies "With Carlos at Izzy Clipz, 1919 Mission Ave." Times are shop time.
    public static func reminders(
        for appointment: Appointment,
        shopName: String,
        address: String,
        calendar: BookingCalendar,
        now: Date
    ) -> [AppointmentReminder] {
        let barber = appointment.barberID == nil ? "the first available barber" : appointment.barberName
        let place = address.isEmpty ? shopName : "\(shopName), \(address)"
        let body = "With \(barber) at \(place)" + (place.hasSuffix(".") ? "" : ".")
        let startDay = calendar.day(containing: appointment.start)
        let time = calendar.timeLabel(for: appointment.start)

        return AppointmentReminderKind.allCases.compactMap { kind in
            let date = appointment.start.addingTimeInterval(-kind.leadTime)
            guard date > now else { return nil }
            let fireDay = calendar.day(containing: date)
            let when: String
            if startDay == fireDay {
                when = "at \(time)"
            } else if startDay == fireDay.adding(days: 1) {
                when = "tomorrow at \(time)"
            } else {
                when = "on \(calendar.shortLabel(for: startDay)) at \(time)"
            }
            return AppointmentReminder(kind: kind, date: date, title: "\(appointment.serviceName) \(when)", body: body)
        }
    }

    /// Stored form of saved appointments: a JSON array.
    public static func encode(_ appointments: [Appointment]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Dates round-trip exactly as seconds since the reference date.
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(appointments)
    }

    /// Reads what `encode` wrote. Entries that can't be read are skipped, so
    /// one bad entry never loses the rest; it only throws when `data` isn't a
    /// JSON array.
    public static func decode(_ data: Data) throws -> [Appointment] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode([Lossy<Appointment>].self, from: data).decodedValues()
    }

    /// By start, then by when they were saved, so the order is stable.
    private static func sorted(_ appointments: [Appointment]) -> [Appointment] {
        appointments.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
