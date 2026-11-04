import Foundation

// Analytics for the whole shop and for each barber, built by the server from its sales and
// appointments (server/src/analytics.ts; every number is explained in plain words in
// docs/analytics.md). Models field for field as the server writes them.

extension IzzyAPI {
    /// `GET /api/owner/analytics?from=YYYY-MM-DD&to=YYYY-MM-DD[&barberId=…]`: shop-local days, both
    /// included, at most `maxDays` long.
    public struct AnalyticsQuery: Hashable, Sendable {
        public var from: LocalDate
        public var to: LocalDate
        /// One barber, or `nil` for the whole shop.
        public var barberId: String?

        public init(from: LocalDate, to: LocalDate, barberId: String? = nil) {
            self.from = from
            self.to = to
            self.barberId = barberId
        }

        /// One shop day.
        public init(day: LocalDate, barberId: String? = nil) {
            self.init(from: day, to: day, barberId: barberId)
        }

        /// The longest range the server answers.
        public static let maxDays = 366
        /// Ranges up to this long come back by day; longer ones by month.
        public static let maxDailyDays = 62

        /// How many days the range covers, both ends included (0 when `to` is before `from`).
        public var dayCount: Int {
            max(0, to.calendarDay.dayNumber - from.calendarDay.dayNumber + 1)
        }

        /// Whether the server will take it: `from` no later than `to`, at most `maxDays` days.
        public var isValid: Bool {
            (1...Self.maxDays).contains(dayCount)
        }

        /// How the server will split the series: by day up to `maxDailyDays` days, by month beyond.
        public var granularity: Analytics.Granularity {
            dayCount <= Self.maxDailyDays ? .day : .month
        }

        /// The same-length period right before `from`, which the server compares with (`Analytics.previous`).
        public var previousPeriod: (from: LocalDate, to: LocalDate) {
            (from.adding(days: -dayCount), from.adding(days: -1))
        }
    }

    /// `GET /api/owner/analytics` → `{ from, to, barberId, timeZone, generatedAt, granularity, totals,
    /// previous, productivity, topBarber, leaderboard, services, products, series, barbers }`.
    ///
    /// With a `barberId`, `totals`, `previous`, `productivity`, `services`, `products` and `series` are
    /// that barber's; `topBarber` and `leaderboard` are always the whole shop's.
    public struct Analytics: Codable, Hashable, Sendable {
        /// How `series` is split.
        public enum Granularity: String, Codable, CaseIterable, Hashable, Sendable {
            /// One entry per day ("2026-11-01"): ranges up to 62 days.
            case day
            /// One entry per month ("2026-11"): longer ranges.
            case month

            /// A split this version doesn't know reads as `day`; each `Period.start` is then `nil` when
            /// its date isn't a day.
            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Granularity(rawValue: raw) ?? .day
            }
        }

        /// The money and the counts, in cents and items.
        public struct Totals: Codable, Hashable, Sendable {
            /// Services + products + other + fees.
            public var salesCents: Int
            /// Service items of live sales, plus completed appointments that weren't checked out (at their booked price).
            public var servicesCents: Int
            public var productsCents: Int
            /// Custom items, e.g. gift cards.
            public var otherCents: Int
            /// No-show and late-cancellation fees that went through.
            public var feesCents: Int
            public var servicesCount: Int
            /// Products sold, counting quantities.
            public var productsCount: Int
            /// Completed appointments, plus sales without an appointment.
            public var clientsServed: Int
            /// Live sales, plus completed appointments without a sale.
            public var checkouts: Int
            /// (Services + products + other) ÷ checkouts, rounded.
            public var averageTicketCents: Int

            public init(
                salesCents: Int = 0, servicesCents: Int = 0, productsCents: Int = 0, otherCents: Int = 0, feesCents: Int = 0,
                servicesCount: Int = 0, productsCount: Int = 0, clientsServed: Int = 0, checkouts: Int = 0, averageTicketCents: Int = 0
            ) {
                self.salesCents = salesCents
                self.servicesCents = servicesCents
                self.productsCents = productsCents
                self.otherCents = otherCents
                self.feesCents = feesCents
                self.servicesCount = servicesCount
                self.productsCount = productsCount
                self.clientsServed = clientsServed
                self.checkouts = checkouts
                self.averageTicketCents = averageTicketCents
            }
        }

        /// The same-length period right before `from`, for "Up 12% from last week".
        public struct Previous: Codable, Hashable, Sendable {
            public var from: LocalDate
            public var to: LocalDate
            public var salesCents: Int

            public init(from: LocalDate, to: LocalDate, salesCents: Int) {
                self.from = from
                self.to = to
                self.salesCents = salesCents
            }
        }

        /// How busy the chairs were.
        public struct Productivity: Codable, Hashable, Sendable {
            /// Appointments counted by the day they start.
            public struct Appointments: Codable, Hashable, Sendable {
                /// Still booked.
                public var booked: Int
                public var completed: Int
                public var noShows: Int
                public var cancelled: Int
                /// Cancelled by the client inside the agreed late-cancellation window (counted in `cancelled` too).
                public var lateCancellations: Int
                /// Booked and starting after now.
                public var upcoming: Int

                public init(booked: Int = 0, completed: Int = 0, noShows: Int = 0, cancelled: Int = 0, lateCancellations: Int = 0, upcoming: Int = 0) {
                    self.booked = booked
                    self.completed = completed
                    self.noShows = noShows
                    self.cancelled = cancelled
                    self.lateCancellations = lateCancellations
                    self.upcoming = upcoming
                }
            }

            /// The shop's open hours for the barbers, minus time off, up to today.
            public var openMinutes: Int
            /// Booked and completed appointments in those days.
            public var bookedMinutes: Int
            /// `bookedMinutes` ÷ `openMinutes`: a ratio that can pass 1 (see `chairTimeBookedShown`).
            public var chairTimeBooked: Double
            public var appointments: Appointments
            /// Completed ÷ (completed + no-shows).
            public var completionRate: Double
            /// No-shows ÷ (completed + no-shows).
            public var noShowRate: Double
            /// (Services + products + other) per open hour.
            public var salesPerHourCents: Int
            /// Live sales with a product ÷ live sales.
            public var productAttachRate: Double

            public init(
                openMinutes: Int = 0, bookedMinutes: Int = 0, chairTimeBooked: Double = 0, appointments: Appointments = Appointments(),
                completionRate: Double = 0, noShowRate: Double = 0, salesPerHourCents: Int = 0, productAttachRate: Double = 0
            ) {
                self.openMinutes = openMinutes
                self.bookedMinutes = bookedMinutes
                self.chairTimeBooked = chairTimeBooked
                self.appointments = appointments
                self.completionRate = completionRate
                self.noShowRate = noShowRate
                self.salesPerHourCents = salesPerHourCents
                self.productAttachRate = productAttachRate
            }

            /// "Chair time booked" as shown: capped at 100% (and never below 0).
            public var chairTimeBookedShown: Double {
                min(max(chairTimeBooked, 0), 1)
            }
        }

        /// The whole shop's top sales barber: `{ barberId, name, salesCents, servicesCount, productsCount }`.
        public struct TopBarber: Codable, Hashable, Sendable {
            public var barberId: String
            public var name: String
            public var salesCents: Int
            public var servicesCount: Int
            public var productsCount: Int

            public init(barberId: String, name: String, salesCents: Int, servicesCount: Int, productsCount: Int) {
                self.barberId = barberId
                self.name = name
                self.salesCents = salesCents
                self.servicesCount = servicesCount
                self.productsCount = productsCount
            }
        }

        /// One barber on the leaderboard (every active barber, even at $0).
        public struct LeaderboardEntry: Codable, Hashable, Identifiable, Sendable {
            /// 1 for the most sales; barbers who tie share a rank.
            public var rank: Int
            public var barberId: String
            public var name: String
            public var salesCents: Int
            public var servicesCents: Int
            public var productsCents: Int
            public var servicesCount: Int
            public var productsCount: Int
            public var clientsServed: Int
            public var averageTicketCents: Int

            public init(
                rank: Int, barberId: String, name: String, salesCents: Int = 0, servicesCents: Int = 0, productsCents: Int = 0,
                servicesCount: Int = 0, productsCount: Int = 0, clientsServed: Int = 0, averageTicketCents: Int = 0
            ) {
                self.rank = rank
                self.barberId = barberId
                self.name = name
                self.salesCents = salesCents
                self.servicesCents = servicesCents
                self.productsCents = productsCents
                self.servicesCount = servicesCount
                self.productsCount = productsCount
                self.clientsServed = clientsServed
                self.averageTicketCents = averageTicketCents
            }

            public var id: String { barberId }
        }

        /// One service's sales (top sales by service), most first.
        public struct ServiceSales: Codable, Hashable, Identifiable, Sendable {
            public var serviceId: String
            public var name: String
            public var count: Int
            public var salesCents: Int

            public init(serviceId: String, name: String, count: Int, salesCents: Int) {
                self.serviceId = serviceId
                self.name = name
                self.count = count
                self.salesCents = salesCents
            }

            public var id: String { serviceId }
        }

        /// One product's sales, most first.
        public struct ProductSales: Codable, Hashable, Sendable {
            /// `nil` for a product deleted since; its name stays.
            public var productId: String?
            public var name: String
            /// How many were sold.
            public var quantity: Int
            public var salesCents: Int

            public init(productId: String?, name: String, quantity: Int, salesCents: Int) {
                self.productId = productId
                self.name = name
                self.quantity = quantity
                self.salesCents = salesCents
            }

            private enum CodingKeys: String, CodingKey {
                case productId, name, quantity, salesCents
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(productId, forKey: .productId)
                try container.encode(name, forKey: .name)
                try container.encode(quantity, forKey: .quantity)
                try container.encode(salesCents, forKey: .salesCents)
            }
        }

        /// One day (or month) of the series; every day or month in the range is there, zeros included.
        public struct Period: Codable, Hashable, Identifiable, Sendable {
            /// "2026-11-01" by day, "2026-11" by month.
            public var date: String
            public var salesCents: Int
            public var servicesCents: Int
            public var productsCents: Int
            public var otherCents: Int
            public var feesCents: Int
            public var servicesCount: Int
            public var productsCount: Int

            public init(
                date: String, salesCents: Int = 0, servicesCents: Int = 0, productsCents: Int = 0, otherCents: Int = 0, feesCents: Int = 0,
                servicesCount: Int = 0, productsCount: Int = 0
            ) {
                self.date = date
                self.salesCents = salesCents
                self.servicesCents = servicesCents
                self.productsCents = productsCents
                self.otherCents = otherCents
                self.feesCents = feesCents
                self.servicesCount = servicesCount
                self.productsCount = productsCount
            }

            public var id: String { date }

            /// The day, or a month's first day; `nil` for a date in neither form.
            public var start: LocalDate? {
                LocalDate(date) ?? LocalDate(date + "-01")
            }

            /// Whether this is a whole month ("2026-11").
            public var isMonth: Bool {
                LocalDate(date) == nil && LocalDate(date + "-01") != nil
            }
        }

        /// A barber the scope picker offers: `{ barberId, name }`.
        public struct Barber: Codable, Hashable, Identifiable, Sendable {
            public var barberId: String
            public var name: String

            public init(barberId: String, name: String) {
                self.barberId = barberId
                self.name = name
            }

            public var id: String { barberId }
        }

        public var from: LocalDate
        public var to: LocalDate
        /// The barber it's filtered by, or `nil` for the whole shop.
        public var barberId: String?
        /// The shop's IANA time zone, e.g. "America/Los_Angeles": the days are its days.
        public var timeZone: String
        /// When the server worked it out ("Live · Updated 10:42 AM").
        public var generatedAt: Date
        public var granularity: Granularity
        public var totals: Totals
        public var previous: Previous
        public var productivity: Productivity
        /// The whole shop's top sales barber, or `nil` while nobody has sales.
        public var topBarber: TopBarber?
        /// The whole shop, best first.
        public var leaderboard: [LeaderboardEntry]
        public var services: [ServiceSales]
        public var products: [ProductSales]
        public var series: [Period]
        public var barbers: [Barber]

        public init(
            from: LocalDate,
            to: LocalDate,
            barberId: String? = nil,
            timeZone: String,
            generatedAt: Date,
            granularity: Granularity = .day,
            totals: Totals = Totals(),
            previous: Previous,
            productivity: Productivity = Productivity(),
            topBarber: TopBarber? = nil,
            leaderboard: [LeaderboardEntry] = [],
            services: [ServiceSales] = [],
            products: [ProductSales] = [],
            series: [Period] = [],
            barbers: [Barber] = []
        ) {
            self.from = from
            self.to = to
            self.barberId = barberId
            self.timeZone = timeZone
            self.generatedAt = generatedAt
            self.granularity = granularity
            self.totals = totals
            self.previous = previous
            self.productivity = productivity
            self.topBarber = topBarber
            self.leaderboard = leaderboard
            self.services = services
            self.products = products
            self.series = series
            self.barbers = barbers
        }

        /// `nil` if the server sent a name this device doesn't know.
        public var shopTimeZone: TimeZone? { TimeZone(identifier: timeZone) }

        /// The change in sales from `previous`, e.g. 0.12 for "Up 12%" or -0.5 for "Down 50%"; `nil`
        /// when the previous period had no sales ("No sales last week").
        public var salesChange: Double? {
            guard previous.salesCents > 0 else { return nil }
            return Double(totals.salesCents - previous.salesCents) / Double(previous.salesCents)
        }

        /// The leaderboard entry for `barberId` (to highlight the barber picked), if any.
        public func entry(for barberId: String) -> LeaderboardEntry? {
            leaderboard.first { $0.barberId == barberId }
        }

        private enum CodingKeys: String, CodingKey {
            case from, to, barberId, timeZone, generatedAt, granularity, totals, previous, productivity, topBarber
            case leaderboard, services, products, series, barbers
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(barberId, forKey: .barberId)
            try container.encode(timeZone, forKey: .timeZone)
            try container.encode(generatedAt, forKey: .generatedAt)
            try container.encode(granularity, forKey: .granularity)
            try container.encode(totals, forKey: .totals)
            try container.encode(previous, forKey: .previous)
            try container.encode(productivity, forKey: .productivity)
            try container.encode(topBarber, forKey: .topBarber)
            try container.encode(leaderboard, forKey: .leaderboard)
            try container.encode(services, forKey: .services)
            try container.encode(products, forKey: .products)
            try container.encode(series, forKey: .series)
            try container.encode(barbers, forKey: .barbers)
        }
    }
}
