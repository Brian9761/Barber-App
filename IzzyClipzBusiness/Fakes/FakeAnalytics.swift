import Foundation
import IzzyClipzKit

/// `GET /api/owner/analytics` for the sample server: the server's own definitions
/// (`computeAnalytics` in server/src/analytics.ts, in plain words in docs/analytics.md), worked out
/// the same way from the sample server's appointments, sales, fees and time off. So the demo, the
/// UI tests and previews show live numbers: a checkout, a visit marked Done or a fee shows up the
/// next time Analytics asks. `FakeAnalyticsTests` checks each definition.
///
/// Like the server, it never looks at clients' names, numbers, emails or notes, so removing them
/// after 12 months (the Privacy Policy) never changes a number.
enum FakeAnalytics {
    /// What the numbers are worked out from.
    struct Records {
        var appointments: [IzzyAPI.Appointment]
        /// Every sale, voided ones too.
        var sales: [IzzyAPI.Sale]
        var timeOff: [IzzyAPI.TimeOff]
        /// The products there are now: a sold product that's gone since counts under the name it
        /// was sold by, like the server's `product_id` set to null on delete.
        var products: [IzzyAPI.Product]
    }

    /// How far from today `from` and `to` may be, either way (`MAX_DAYS_FROM_TODAY`).
    static let maxDaysFromToday = 3_660

    /// The analytics JSON the server would send for `query` at `now`. Throws the server's 400s.
    static func analytics(
        _ query: IzzyAPI.AnalyticsQuery,
        records: Records,
        catalog: Catalog,
        shopTime: ShopTime,
        now: Date
    ) throws -> IzzyAPI.Analytics {
        let today = shopTime.day(containing: now)
        func invalid(_ message: String) -> APIError {
            APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: message, status: 400)
        }
        if abs(days(from: today, to: query.from)) > maxDaysFromToday || abs(days(from: today, to: query.to)) > maxDaysFromToday {
            throw invalid("Pick dates within 10 years of today.")
        }
        let span = days(from: query.from, to: query.to)
        if span < 0 { throw invalid("to must be on or after from.") }
        if span >= IzzyAPI.AnalyticsQuery.maxDays { throw invalid("Ask for at most \(IzzyAPI.AnalyticsQuery.maxDays) days at a time.") }
        // Every barber in the sample server is on the team.
        let team = catalog.barbers
        if let barberId = query.barberId, !team.contains(where: { $0.id == barberId }) {
            throw invalid("That barber isn't on the team.")
        }

        let (granularity, periods) = seriesPeriods(from: query.from, to: query.to)
        let previous = (from: query.from.adding(days: -(span + 1)), to: query.from.adding(days: -1))
        // Where each period starts, the previous period first, and where the range ends: shop-local
        // midnights, like the server's `width_bucket` edges.
        let edges = ([previous.from] + periods.map(\.from) + [query.to.adding(days: 1)]).map(shopTime.startOfDay)
        /// Where an instant falls: the previous period, a series period, or outside both.
        func bucket(_ instant: Date) -> Bucket? {
            guard let first = edges.first, let last = edges.last, instant >= first, instant < last else { return nil }
            // The last edge at or before the instant.
            var low = 0
            var high = edges.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if edges[middle] <= instant { low = middle } else { high = middle }
            }
            return low == 0 ? .previous : .period(low - 1)
        }

        // Money: items of live sales, completed appointments with no live sale, and fees Stripe charged.
        var money: [MoneyFact] = []
        let liveSales = records.sales.filter { $0.voidedAt == nil }
        let checkedOut = Set(liveSales.compactMap(\.appointmentId))
        let products = Dictionary(records.products.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for sale in liveSales {
            guard let bucket = bucket(sale.soldAt) else { continue }
            for item in sale.items {
                switch item.kind {
                case .service:
                    money.append(MoneyFact(bucket: bucket, barberId: sale.barberId, kind: .service, visit: false,
                                           itemId: item.serviceId, name: item.name, count: item.quantity, cents: item.totalCents))
                case .product:
                    // A product deleted since has no id any more: it's listed by the name it was sold under.
                    let current = item.productId.flatMap { products[$0] }
                    money.append(MoneyFact(bucket: bucket, barberId: sale.barberId, kind: .product, visit: false,
                                           itemId: current == nil ? nil : item.productId, name: current ?? item.name,
                                           count: item.quantity, cents: item.totalCents))
                case .custom:
                    money.append(MoneyFact(bucket: bucket, barberId: sale.barberId, kind: .custom, visit: false,
                                           itemId: nil, name: item.name, count: item.quantity, cents: item.totalCents))
                }
            }
        }
        for appointment in records.appointments where appointment.status == .completed && !checkedOut.contains(appointment.id) {
            guard let bucket = bucket(appointment.start) else { continue }
            money.append(MoneyFact(bucket: bucket, barberId: appointment.barberId, kind: .service, visit: true,
                                   itemId: appointment.serviceId, name: appointment.serviceName, count: 1,
                                   cents: bookedPrice(of: appointment, catalog: catalog)))
        }
        for appointment in records.appointments {
            // A fee counts the day Stripe charged it, for the appointment's barber.
            guard let fee = appointment.noShowFee, fee.status == .charged, let chargedAt = fee.chargedAt,
                  let bucket = bucket(chargedAt) else { continue }
            money.append(MoneyFact(bucket: bucket, barberId: appointment.barberId, kind: .fee, visit: false,
                                   itemId: nil, name: "", count: 1, cents: fee.amountCents))
        }

        // Sales in the range (by when they were sold), and appointments in it (by their start's day).
        let rangeStart = shopTime.startOfDay(query.from)
        let rangeEnd = shopTime.startOfDay(query.to.adding(days: 1))
        let todayEnd = shopTime.startOfDay(today.adding(days: 1))
        var saleCounts: [String: SaleCounts] = [:]
        for sale in liveSales where sale.soldAt >= rangeStart && sale.soldAt < rangeEnd {
            var counts = saleCounts[sale.barberId] ?? SaleCounts()
            counts.sales += 1
            if sale.appointmentId == nil { counts.withoutAppointment += 1 }
            if sale.items.contains(where: { $0.kind == .product }) { counts.withProduct += 1 }
            saleCounts[sale.barberId] = counts
        }
        var appointmentCounts: [String: AppointmentCounts] = [:]
        for appointment in records.appointments where appointment.start >= rangeStart && appointment.start < rangeEnd {
            var counts = appointmentCounts[appointment.barberId] ?? AppointmentCounts()
            switch appointment.status {
            case .booked:
                counts.booked += 1
                if appointment.start > now { counts.upcoming += 1 }
            case .completed: counts.completed += 1
            case .noShow: counts.noShows += 1
            case .cancelled:
                counts.cancelled += 1
                if isLateCancellation(appointment) { counts.lateCancellations += 1 }
            }
            if appointment.status == .booked || appointment.status == .completed, appointment.start < todayEnd {
                counts.bookedMinutes += Int((appointment.end.timeIntervalSince(appointment.start) / 60).rounded())
            }
            appointmentCounts[appointment.barberId] = counts
        }

        // The definitions (computeAnalytics): the selection's numbers, each barber's for the
        // leaderboard, and each period's for the series.
        func selected(_ barberId: String?) -> Bool { query.barberId == nil || barberId == query.barberId }
        var scope = Tally()
        var perBarber = Dictionary(uniqueKeysWithValues: team.map { ($0.id, Tally()) })
        var perPeriod = Array(repeating: Tally(), count: periods.count)
        var previousCents = 0
        var services: [String: IzzyAPI.Analytics.ServiceSales] = [:]
        var serviceOrder: [String] = []
        var productLines: [String: IzzyAPI.Analytics.ProductSales] = [:]
        var productOrder: [String] = []
        for fact in money {
            guard case .period(let index) = fact.bucket else {
                if selected(fact.barberId) { previousCents += fact.cents }
                continue
            }
            if let barberId = fact.barberId, perBarber[barberId] != nil { perBarber[barberId]?.add(fact) }
            guard selected(fact.barberId) else { continue }
            scope.add(fact)
            perPeriod[index].add(fact)
            if fact.kind == .service, let serviceId = fact.itemId {
                if services[serviceId] == nil {
                    services[serviceId] = IzzyAPI.Analytics.ServiceSales(
                        serviceId: serviceId, name: catalog.service(withID: serviceId)?.name ?? fact.name, count: 0, salesCents: 0
                    )
                    serviceOrder.append(serviceId)
                }
                services[serviceId]?.count += fact.count
                services[serviceId]?.salesCents += fact.cents
            } else if fact.kind == .product {
                let key = fact.itemId ?? "deleted:\(fact.name)"
                if productLines[key] == nil {
                    productLines[key] = IzzyAPI.Analytics.ProductSales(productId: fact.itemId, name: fact.name, quantity: 0, salesCents: 0)
                    productOrder.append(key)
                }
                productLines[key]?.quantity += fact.count
                productLines[key]?.salesCents += fact.cents
            }
        }
        for (barberId, counts) in saleCounts {
            perBarber[barberId]?.add(counts)
            if selected(barberId) { scope.add(counts) }
        }
        var appointments = IzzyAPI.Analytics.Productivity.Appointments()
        var bookedMinutes = 0
        for (barberId, counts) in appointmentCounts {
            perBarber[barberId]?.completed += counts.completed
            guard selected(barberId) else { continue }
            scope.completed += counts.completed
            appointments.booked += counts.booked
            appointments.completed += counts.completed
            appointments.noShows += counts.noShows
            appointments.cancelled += counts.cancelled
            appointments.lateCancellations += counts.lateCancellations
            appointments.upcoming += counts.upcoming
            bookedMinutes += counts.bookedMinutes
        }
        let open = team.filter { selected($0.id) }
            .reduce(0) { $0 + openMinutes(barberId: $1.id, from: query.from, to: query.to, today: today, timeOff: records.timeOff, shopTime: shopTime) }
        let visitsWithOutcome = appointments.completed + appointments.noShows

        let leaderboard = rankLeaderboard(team.map { barber in
            let tally = perBarber[barber.id] ?? Tally()
            return IzzyAPI.Analytics.LeaderboardEntry(
                rank: 0, barberId: barber.id, name: barber.name, salesCents: tally.salesCents,
                servicesCents: tally.servicesCents, productsCents: tally.productsCents,
                servicesCount: tally.servicesCount, productsCount: tally.productsCount,
                clientsServed: tally.clientsServed, averageTicketCents: tally.averageTicketCents
            )
        })
        let topBarber = leaderboard.first.flatMap { first in
            first.salesCents > 0
                ? IzzyAPI.Analytics.TopBarber(barberId: first.barberId, name: first.name, salesCents: first.salesCents,
                                              servicesCount: first.servicesCount, productsCount: first.productsCount)
                : nil
        }

        return IzzyAPI.Analytics(
            from: query.from,
            to: query.to,
            barberId: query.barberId,
            timeZone: shopTime.shop.timeZoneIdentifier,
            // The server writes whole seconds.
            generatedAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)),
            granularity: granularity,
            totals: scope.totals,
            previous: IzzyAPI.Analytics.Previous(from: previous.from, to: previous.to, salesCents: previousCents),
            productivity: IzzyAPI.Analytics.Productivity(
                openMinutes: open,
                bookedMinutes: bookedMinutes,
                chairTimeBooked: ratio(bookedMinutes, open),
                appointments: appointments,
                completionRate: ratio(appointments.completed, visitsWithOutcome),
                noShowRate: ratio(appointments.noShows, visitsWithOutcome),
                salesPerHourCents: roundedRatio(scope.soldCents * 60, open),
                productAttachRate: ratio(scope.salesWithProduct, scope.sales)
            ),
            topBarber: topBarber,
            leaderboard: leaderboard,
            services: serviceOrder.compactMap { services[$0] }.sorted {
                $0.salesCents != $1.salesCents ? $0.salesCents > $1.salesCents
                    : $0.count != $1.count ? $0.count > $1.count : byName($0.name, $1.name)
            },
            products: productOrder.compactMap { productLines[$0] }.sorted {
                $0.salesCents != $1.salesCents ? $0.salesCents > $1.salesCents
                    : $0.quantity != $1.quantity ? $0.quantity > $1.quantity : byName($0.name, $1.name)
            },
            series: periods.enumerated().map { index, period in perPeriod[index].period(period.label) },
            barbers: team.map { IzzyAPI.Analytics.Barber(barberId: $0.id, name: $0.name) }
        )
    }

    // MARK: The server's helpers

    /// Days from `from` to `to`: negative when `to` is earlier.
    static func days(from: LocalDate, to: LocalDate) -> Int {
        AnalyticsDayRange.days(from: from, to: to)
    }

    /// One series entry's days: a single day ("2026-11-01"), or the part of a month ("2026-11")
    /// inside the range.
    struct Period: Equatable {
        let label: String
        let from: LocalDate
        let to: LocalDate
    }

    /// `seriesPeriods`: one entry per day for 62 days or fewer, otherwise one per calendar month;
    /// every day or month in the range, zeros included.
    static func seriesPeriods(from: LocalDate, to: LocalDate) -> (IzzyAPI.Analytics.Granularity, [Period]) {
        let count = days(from: from, to: to) + 1
        if count <= IzzyAPI.AnalyticsQuery.maxDailyDays {
            return (.day, (0..<count).map { offset in
                let day = from.adding(days: offset)
                return Period(label: day.description, from: day, to: day)
            })
        }
        var periods: [Period] = []
        var start = from
        while start <= to {
            let next = start.month == 12
                ? LocalDate(year: start.year + 1, month: 1, day: 1)
                : LocalDate(year: start.year, month: start.month + 1, day: 1)
            guard let next else { break }
            let last = next.adding(days: -1)
            periods.append(Period(label: String(start.description.prefix(7)), from: start, to: min(last, to)))
            start = next
        }
        return (.month, periods)
    }

    /// `openMinutes` for one barber: for each day of the range up to and including today, the
    /// shop's hours that day minus the time off that overlaps them (his own or the whole shop's;
    /// blocks that overlap each other count once). A day after today, or a closed day, counts 0.
    static func openMinutes(barberId: String, from: LocalDate, to: LocalDate, today: LocalDate, timeOff: [IzzyAPI.TimeOff], shopTime: ShopTime) -> Int {
        var total: TimeInterval = 0
        var day = from
        while day <= to, day <= today {
            defer { day = day.adding(days: 1) }
            guard let open = shopTime.openInterval(on: day), open.end > open.start else { continue }
            let blocks = timeOff
                .filter { ($0.barberId == nil || $0.barberId == barberId) && $0.start < open.end && $0.end > open.start }
                .map { (start: max($0.start, open.start), end: min($0.end, open.end)) }
                .sorted { $0.start < $1.start }
            var off: TimeInterval = 0
            var covered = open.start
            for block in blocks {
                let start = max(block.start, covered)
                if block.end > start {
                    off += block.end.timeIntervalSince(start)
                    covered = block.end
                }
            }
            total += open.end.timeIntervalSince(open.start) - off
        }
        return Int((total / 60 + 0.5).rounded(.down))
    }

    /// The price an appointment was booked at: its offering's (the server keeps it on the appointment).
    static func bookedPrice(of appointment: IzzyAPI.Appointment, catalog: Catalog) -> Int {
        if let offering = catalog.offering(withID: appointment.offeringId) { return offering.price.cents }
        // An offering that's gone: the price its label shows ("$35", "From $80").
        let digits = appointment.priceLabel.drop { $0 != "$" }.dropFirst().prefix { $0.isNumber || $0 == "," || $0 == "." }
        let parts = digits.replacingOccurrences(of: ",", with: "").split(separator: ".")
        let dollars = parts.first.flatMap { Int($0) } ?? 0
        let cents = parts.count > 1 ? Int(parts[1].prefix(2).padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0 : 0
        return dollars * 100 + cents
    }

    /// A late cancellation (feecase.ts `cancelledLate`): cancelled by the client in the app, with a
    /// card on file and its fee, less than the agreed window before the start and more than 15
    /// minutes after booking. A booking whose policy had no window is never late.
    static func isLateCancellation(_ appointment: IzzyAPI.Appointment) -> Bool {
        guard appointment.status == .cancelled, appointment.cancelledBy == .customer, appointment.card != nil,
              let fee = appointment.noShowFee, let window = fee.lateCancelWindowMinutes, let cancelledAt = fee.customerCancelledAt
        else { return false }
        return IzzyAPI.NoShowRule.cancelledLate(
            start: appointment.start, customerCancelledAt: cancelledAt, lateCancelWindowMinutes: window, createdAt: appointment.createdAt
        )
    }

    /// round(numerator / denominator), halves up, or 0 when the denominator is 0.
    static func roundedRatio(_ numerator: Int, _ denominator: Int) -> Int {
        denominator > 0 ? (2 * numerator + denominator) / (2 * denominator) : 0
    }

    /// numerator / denominator, or 0 when the denominator is 0.
    static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator > 0 ? Double(numerator) / Double(denominator) : 0
    }

    /// Names A to Z, as the server sorts them.
    static func byName(_ a: String, _ b: String) -> Bool {
        let (left, right) = (a.lowercased(), b.lowercased())
        return left != right ? left < right : a < b
    }

    /// `rankLeaderboard`: sales high to low, then services, then name; barbers with the same sales
    /// and the same number of services share a rank, and the next one skips (1, 1, 3).
    static func rankLeaderboard(_ entries: [IzzyAPI.Analytics.LeaderboardEntry]) -> [IzzyAPI.Analytics.LeaderboardEntry] {
        let sorted = entries.sorted {
            $0.salesCents != $1.salesCents ? $0.salesCents > $1.salesCents
                : $0.servicesCount != $1.servicesCount ? $0.servicesCount > $1.servicesCount : byName($0.name, $1.name)
        }
        var rank = 0
        return sorted.enumerated().map { index, entry in
            if index == 0 || sorted[index - 1].salesCents != entry.salesCents || sorted[index - 1].servicesCount != entry.servicesCount {
                rank = index + 1
            }
            var ranked = entry
            ranked.rank = rank
            return ranked
        }
    }

    // MARK: Adding up

    private enum Bucket: Equatable {
        case previous
        case period(Int)
    }

    private enum Kind: Equatable {
        case service, product, custom, fee
    }

    /// Money of one kind: an item of a live sale, a completed appointment without one (`visit`), or a fee.
    private struct MoneyFact {
        let bucket: Bucket
        let barberId: String?
        let kind: Kind
        let visit: Bool
        /// Services: the service. Products: the product, or `nil` once deleted.
        let itemId: String?
        let name: String
        let count: Int
        let cents: Int
    }

    private struct SaleCounts {
        var sales = 0
        var withoutAppointment = 0
        var withProduct = 0
    }

    private struct AppointmentCounts {
        var booked = 0
        var completed = 0
        var noShows = 0
        var cancelled = 0
        var lateCancellations = 0
        var upcoming = 0
        var bookedMinutes = 0
    }

    /// What one barber, the selection or one period sold and did.
    private struct Tally {
        var servicesCents = 0
        var servicesCount = 0
        var productsCents = 0
        var productsCount = 0
        var otherCents = 0
        var feesCents = 0
        var sales = 0
        var salesWithoutAppointment = 0
        var salesWithProduct = 0
        /// Completed appointments without a live sale.
        var visits = 0
        /// All completed appointments.
        var completed = 0

        mutating func add(_ fact: MoneyFact) {
            switch fact.kind {
            case .service:
                servicesCents += fact.cents
                servicesCount += fact.count
                if fact.visit { visits += fact.count }
            case .product:
                productsCents += fact.cents
                productsCount += fact.count
            case .custom:
                otherCents += fact.cents
            case .fee:
                feesCents += fact.cents
            }
        }

        mutating func add(_ counts: SaleCounts) {
            sales += counts.sales
            salesWithoutAppointment += counts.withoutAppointment
            salesWithProduct += counts.withProduct
        }

        /// Services + products + other + fees.
        var salesCents: Int { servicesCents + productsCents + otherCents + feesCents }
        /// Services + products + other: what was sold, without the fees.
        var soldCents: Int { servicesCents + productsCents + otherCents }
        /// Live sales + completed appointments without one.
        var checkouts: Int { sales + visits }
        /// Completed appointments + live sales without an appointment.
        var clientsServed: Int { completed + salesWithoutAppointment }
        var averageTicketCents: Int { FakeAnalytics.roundedRatio(soldCents, checkouts) }

        var totals: IzzyAPI.Analytics.Totals {
            IzzyAPI.Analytics.Totals(
                salesCents: salesCents, servicesCents: servicesCents, productsCents: productsCents, otherCents: otherCents,
                feesCents: feesCents, servicesCount: servicesCount, productsCount: productsCount, clientsServed: clientsServed,
                checkouts: checkouts, averageTicketCents: averageTicketCents
            )
        }

        func period(_ label: String) -> IzzyAPI.Analytics.Period {
            IzzyAPI.Analytics.Period(
                date: label, salesCents: salesCents, servicesCents: servicesCents, productsCents: productsCents,
                otherCents: otherCents, feesCents: feesCents, servicesCount: servicesCount, productsCount: productsCount
            )
        }
    }
}

extension FakeServer {
    /// `GET /api/owner/analytics`: the numbers worked out from the sample server's own appointments,
    /// sales (with the sample history, `Options.sampleHistory`), fees and time off.
    func analytics(_ query: IzzyAPI.AnalyticsQuery) throws -> IzzyAPI.Analytics {
        try FakeAnalytics.analytics(
            query,
            records: FakeAnalytics.Records(appointments: appointments, sales: sales, timeOff: timeOff, products: products),
            catalog: catalog, shopTime: shopTime, now: now()
        )
    }
}

extension FakeOwnerAPI {
    func analytics(_ query: IzzyAPI.AnalyticsQuery) async throws -> IzzyAPI.Analytics {
        try await server.begin("analytics", key: ownerKey)
        return try await server.analytics(query)
    }
}
