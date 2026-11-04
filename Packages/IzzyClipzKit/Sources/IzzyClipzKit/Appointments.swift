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
    /// An hour before free cancelling ends, for an appointment whose late cancellations may be
    /// charged (`LateCancelTerms`), when neither of the others comes while cancelling is still free.
    case freeCancelEnds

    /// How long before the start the reminder fires; for `freeCancelEnds`, how long before free
    /// cancelling ends.
    public var leadTime: TimeInterval {
        switch self {
        case .dayBefore: return 24 * 60 * 60
        case .hourBefore, .freeCancelEnds: return 60 * 60
        }
    }
}

/// What cancelling an appointment late may cost, for its reminders: it was booked with a card on
/// file under a policy that charges late cancellations (`IzzyAPI.Appointment.lateCancelTerms`).
public struct LateCancelTerms: Hashable, Sendable {
    /// Cancelling less than this many minutes before the start may be charged.
    public var windowMinutes: Int
    /// The fee: "$45".
    public var feeLabel: String

    public init(windowMinutes: Int, feeLabel: String) {
        self.windowMinutes = windowMinutes
        self.feeLabel = feeLabel
    }

    /// The last moment cancelling an appointment that starts at `start` is free: exactly the
    /// window before it (less than that is late, as the server counts it).
    public func freeUntil(start: Date) -> Date {
        start.addingTimeInterval(-TimeInterval(windowMinutes) * 60)
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

    /// The reminders that are still in the future, soonest first: the day before and an hour before.
    ///
    /// Titles read "Haircut tomorrow at 2:30 PM" and "Haircut at 2:30 PM";
    /// bodies "With Carlos at Izzy Clipz, 1919 Mission Ave." Times are shop time.
    ///
    /// With `lateCancel` (a card on file, under a policy that charges late cancellations), each
    /// body also says where the client stands then: "Can't make it? Cancel in the app by 1:30 PM
    /// tomorrow so it's free." while cancelling is still free, and "Cancelling now may be charged
    /// $45." once it isn't (with a 1-hour window, the hour-before reminder comes exactly when free
    /// cancelling ends). When neither comes while cancelling is still free, a `freeCancelEnds`
    /// reminder comes an hour before it ends, so the client always hears in time: "Can't make it?
    /// Cancel in the app by 1:30 PM so it's free. After that, cancelling may be charged $45." It
    /// never comes at night: an hour that falls before 8 AM or from 9 PM moves to 8 PM the evening
    /// before (and there's none once that's past).
    public static func reminders(
        for appointment: Appointment,
        shopName: String,
        address: String,
        calendar: BookingCalendar,
        now: Date,
        lateCancel: LateCancelTerms? = nil
    ) -> [AppointmentReminder] {
        let barber = appointment.barberID == nil ? "the first available barber" : appointment.barberName
        let place = address.isEmpty ? shopName : "\(shopName), \(address)"
        let body = "With \(barber) at \(place)" + (place.hasSuffix(".") ? "" : ".")
        let startDay = calendar.day(containing: appointment.start)
        let time = calendar.timeLabel(for: appointment.start)

        /// "Haircut at 2:30 PM", "Haircut tomorrow at 2:30 PM" or "Haircut on Fri, Oct 30 at 2:30 PM",
        /// for a reminder that comes at `date`.
        func title(at date: Date) -> String {
            let day = dayWords(for: startDay, seenOn: calendar.day(containing: date), calendar: calendar)
            return "\(appointment.serviceName) \(day.map { "\($0) at" } ?? "at") \(time)"
        }

        let regular: [AppointmentReminder] = [AppointmentReminderKind.dayBefore, .hourBefore].compactMap { kind in
            let date = appointment.start.addingTimeInterval(-kind.leadTime)
            guard date > now else { return nil }
            return AppointmentReminder(kind: kind, date: date, title: title(at: date), body: body)
        }
        guard let lateCancel else { return regular }

        let freeUntil = lateCancel.freeUntil(start: appointment.start)
        /// "by 1:30 PM", "by 1:30 PM tomorrow" or "by 1:30 PM on Fri, Oct 30", for a reminder at `date`.
        func cancelBy(seenAt date: Date) -> String {
            let day = dayWords(for: calendar.day(containing: freeUntil), seenOn: calendar.day(containing: date), calendar: calendar)
            return "by \(calendar.timeLabel(for: freeUntil))" + (day.map { " \($0)" } ?? "")
        }
        var reminders = regular.map { reminder in
            // Exactly when free cancelling ends counts as too late: the client can't cancel in no time.
            let standing = reminder.date < freeUntil
                ? "Can't make it? Cancel in the app \(cancelBy(seenAt: reminder.date)) so it's free."
                : "Cancelling now may be charged \(lateCancel.feeLabel)."
            return AppointmentReminder(kind: reminder.kind, date: reminder.date, title: reminder.title, body: "\(reminder.body) \(standing)")
        }
        if !reminders.contains(where: { $0.date < freeUntil }),
           let date = freeCancelReminderDate(freeUntil: freeUntil, calendar: calendar, now: now) {
            reminders.append(AppointmentReminder(
                kind: .freeCancelEnds,
                date: date,
                title: title(at: date),
                body: "Can't make it? Cancel in the app \(cancelBy(seenAt: date)) so it's free. "
                    + "After that, cancelling may be charged \(lateCancel.feeLabel)."
            ))
        }
        return reminders.sorted { $0.date < $1.date }
    }

    /// The reminder before free cancelling ends comes between 8 AM and 9 PM, shop time; one that
    /// would come at night comes at 8 PM the evening before.
    static let firstReminderHour = 8
    static let nightStartsHour = 21
    static let eveningReminderHour = 20

    /// When the `freeCancelEnds` reminder comes: an hour before `freeUntil`, or 8 PM the evening
    /// before when that hour is at night. `nil` once it's past.
    static func freeCancelReminderDate(freeUntil: Date, calendar: BookingCalendar, now: Date) -> Date? {
        var date = freeUntil.addingTimeInterval(-AppointmentReminderKind.freeCancelEnds.leadTime)
        let hour = calendar.clock.calendar.component(.hour, from: date)
        if hour < firstReminderHour || hour >= nightStartsHour {
            let day = calendar.day(containing: date).adding(days: hour < firstReminderHour ? -1 : 0)
            guard let evening = calendar.date(on: day, at: TimeOfDay(hour: eveningReminderHour)) else { return nil }
            date = evening
        }
        return date > now ? date : nil
    }

    /// How `day` is said on `seenOn`: `nil` for the same day, "tomorrow", or "on Fri, Oct 30".
    private static func dayWords(for day: CalendarDay, seenOn: CalendarDay, calendar: BookingCalendar) -> String? {
        if day == seenOn { return nil }
        if day == seenOn.adding(days: 1) { return "tomorrow" }
        return "on \(calendar.shortLabel(for: day))"
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
