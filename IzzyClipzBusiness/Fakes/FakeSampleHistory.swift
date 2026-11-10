import Foundation
import IzzyClipzKit

/// The sample shop's last 8 weeks, for Analytics: the sample server's appointments on the 56 days
/// before today, what happened to each, the checkouts (with products, now and then a gift card),
/// walk-ins who bought a cut or a product, and a few no-show and late-cancellation fees charged to
/// a card on file. The same every time for the same today, so the UI tests' numbers don't move.
///
/// What happened follows the server's rules: a checked-out appointment is completed and paid with
/// its sale; a no-show or late-cancellation fee is charged only to a card on file, after the
/// appointment ended (a no-show) or the client cancelled inside the agreed hour (a late
/// cancellation). Clients are "Malik Sample" and so on, with numbers in the 555-01xx range kept for
/// examples, so nothing reads as a real client; and the analytics never look at them anyway.
///
/// Each barber has his own way of working, so the leaderboard's order changes with what it ranks:
/// Izzy sells the most (the owner, with the VIP and Haircut & Beard), Cristian does the most cuts
/// and serves the most clients (quick military cuts), and Carlos sells the most products.
enum FakeSampleHistory {
    /// Days of history before today.
    static let days = 56

    struct History {
        var appointments: [IzzyAPI.Appointment]
        /// Oldest first.
        var sales: [IzzyAPI.Sale]
    }

    /// How a barber works on a usual day.
    struct Profile {
        /// Clients booked: the fewest and the most.
        let clients: ClosedRange<Int>
        /// How often each of his services is booked.
        let weights: [String: Int]
        /// How often a checkout includes a product.
        let productChance: Double
        /// Walk-ins who buy something: the fewest and the most.
        let walkIns: ClosedRange<Int>
    }

    static let profiles: [String: Profile] = [
        "israel-flores": Profile(
            clients: 7...8, weights: ["haircut": 3, "haircut-and-beard": 4, "vip": 4, "hot-towel-shave": 1],
            productChance: 0.25, walkIns: 0...1
        ),
        "carlos-rafael": Profile(
            clients: 4...5, weights: ["haircut": 6, "military-haircut": 3, "haircut-and-beard": 2],
            productChance: 0.6, walkIns: 0...2
        ),
        "flowxbori": Profile(
            clients: 4...6, weights: ["haircut": 6, "haircut-and-beard": 2, "military-haircut": 2, "seniors-haircut": 1, "hot-towel-shave": 1],
            productChance: 0.2, walkIns: 0...1
        ),
        "cristian-ceja": Profile(
            clients: 8...10, weights: ["military-haircut": 6, "haircut": 5, "hot-towel-shave": 2, "haircut-and-beard": 1],
            productChance: 0.1, walkIns: 0...2
        ),
        "julian-ramos": Profile(
            clients: 4...6, weights: ["haircut": 6, "military-haircut": 2, "seniors-haircut": 2, "haircut-and-beard": 2, "hot-towel-shave": 1],
            productChance: 0.2, walkIns: 0...1
        ),
    ]

    /// First names for the sample clients; none of them is one of today's sample clients.
    static let firstNames = [
        "Malik", "Omar", "Ray", "Eli", "Noah", "Gabe", "Isaac", "Jon", "Kevin", "Mateo", "Nate", "Oscar", "Pete", "Ruben", "Theo",
        "Victor", "Will", "Adrian", "Brandon", "Hector", "Ivan", "Jorge", "Leo", "Max", "Rico", "Troy", "Zack", "Evan", "Felix", "Hugo",
    ]

    static let notes = ["Low fade, please.", "First visit.", "Beard trim too, if there's time.", "Same as last time."]

    /// What a product with no price was rung up at.
    static let typedProductCents = 1_500

    /// The 56 days before `now`'s shop day. `products` are the sample server's: priced ones sell at
    /// their price, and one without a price at the price the barber typed.
    static func make(catalog: Catalog, shopTime: ShopTime, now: Date, products: [IzzyAPI.Product]) -> History {
        var maker = Maker(catalog: catalog, shopTime: shopTime, products: products)
        let today = shopTime.day(containing: now)
        for offset in stride(from: days, through: 1, by: -1) {
            maker.addDay(today.adding(days: -offset))
        }
        return History(appointments: maker.appointments, sales: maker.sales)
    }

    /// Builds the history one day at a time.
    private struct Maker {
        let catalog: Catalog
        let shopTime: ShopTime
        let products: [IzzyAPI.Product]
        var appointments: [IzzyAPI.Appointment] = []
        var sales: [IzzyAPI.Sale] = []
        private var appointmentNumber = 0
        private var saleNumber = 0

        init(catalog: Catalog, shopTime: ShopTime, products: [IzzyAPI.Product]) {
            self.catalog = catalog
            self.shopTime = shopTime
            self.products = products
        }

        mutating func addDay(_ day: LocalDate) {
            guard let open = shopTime.openInterval(on: day), open.end > open.start else { return }
            for barber in catalog.barbers {
                guard let profile = profiles[barber.id] else { continue }
                var random = SeededRandom("history|\(day)|\(barber.id)")
                addAppointments(of: barber, profile: profile, open: open, random: &random)
                addWalkIns(of: barber, profile: profile, open: open, random: &random)
            }
        }

        // MARK: Appointments

        private mutating func addAppointments(of barber: Barber, profile: Profile, open: DateInterval, random: inout SeededRandom) {
            let offerings = catalog.offerings(forBarber: barber.id).filter {
                $0.price.kind == .fixed && $0.price.cents > 0 && (profile.weights[$0.serviceID] ?? 0) > 0
            }
            guard !offerings.isEmpty else { return }
            let wanted = random.int(profile.clients)
            var start = open.start.addingTimeInterval(TimeInterval(random.pick([0, 15, 30]) * 60))
            var booked = 0
            while booked < wanted {
                let offering = pick(offerings, weights: profile.weights, random: &random)
                let end = start.addingTimeInterval(TimeInterval(offering.durationMinutes * 60))
                guard end <= open.end else { break }
                addAppointment(offering: offering, barber: barber, start: start, end: end, profile: profile, random: &random)
                booked += 1
                start = end.addingTimeInterval(TimeInterval(random.pick([0, 0, 15, 15, 30, 45, 60]) * 60))
            }
        }

        private mutating func addAppointment(
            offering: Offering, barber: Barber, start: Date, end: Date, profile: Profile, random: inout SeededRandom
        ) {
            appointmentNumber += 1
            let serviceName = catalog.service(withID: offering.serviceID)?.name ?? offering.serviceID
            let hasPhone = random.chance(0.9)
            let customer = IzzyAPI.Customer(
                name: "\(random.pick(firstNames)) Sample",
                phone: hasPhone ? "+144255501\(random.int(20...99))" : nil
            )
            let note = random.chance(0.1) ? random.pick(notes) : nil
            // Some clients booked online with a card on file, under a 1-hour late-cancellation window.
            let hasCard = hasPhone && random.chance(0.25)
            let createdAt = start.addingTimeInterval(-TimeInterval(random.int(1...6) * 86_400 + random.int(0...9) * 3_600))
            var appointment = IzzyAPI.Appointment(
                id: Self.uuid("a000", appointmentNumber),
                offeringId: offering.id,
                serviceId: offering.serviceID,
                serviceName: serviceName,
                barberId: barber.id,
                barberName: barber.name,
                start: start,
                end: end,
                durationMinutes: offering.durationMinutes,
                priceLabel: offering.price.label,
                customer: customer,
                note: note,
                createdAt: createdAt,
                card: hasCard ? IzzyAPI.CardOnFile(brand: random.chance(0.6) ? "visa" : "mastercard", last4: "\(random.int(1_000...9_999))") : nil,
                noShowFee: hasCard ? IzzyAPI.NoShowFee(amountCents: offering.price.cents, fullPrice: true, lateCancelWindowMinutes: 60) : nil
            )

            let outcome = random.next()
            if outcome < 0.76 {
                // Checked out: completed, and paid with the sale.
                var items = [IzzyAPI.SaleItem(kind: .service, serviceId: offering.serviceID, name: serviceName, unitCents: offering.price.cents)]
                if random.chance(profile.productChance), let product = productItem(random: &random) { items.append(product) }
                if random.chance(0.03) { items.append(IzzyAPI.SaleItem(kind: .custom, name: "Gift card", unitCents: 2_500)) }
                let sale = addSale(
                    barber: barber, appointmentId: appointment.id, customerName: customer.name, items: items,
                    soldAt: end.addingTimeInterval(120), random: &random
                )
                appointment.status = .completed
                appointment.sale = IzzyAPI.AppointmentSale(sale: sale)
                appointment.payment = IzzyAPI.AppointmentPayment(status: .paid, amountCents: sale.totalCents, paidAt: sale.soldAt)
            } else if outcome < 0.84 {
                // Marked Done without a checkout: it counts at its booked price.
                appointment.status = .completed
            } else if outcome < 0.91 {
                appointment.status = .noShow
                // A no-show's fee is charged only once the appointment has ended.
                if var fee = appointment.noShowFee, random.chance(0.6) {
                    fee.status = .charged
                    fee.chargedAt = end.addingTimeInterval(600)
                    fee.reason = .noShow
                    appointment.noShowFee = fee
                }
            } else {
                appointment.status = .cancelled
                if random.chance(0.7) {
                    appointment.cancelledBy = .customer
                    let minutesBefore = random.chance(0.35) ? random.int(10...54) : random.int(90...1_290)
                    if var fee = appointment.noShowFee {
                        fee.customerCancelledAt = start.addingTimeInterval(-TimeInterval(minutesBefore * 60))
                        // Less than the hour before (and days after booking): a late cancellation.
                        if minutesBefore < 60, random.chance(0.5) {
                            fee.status = .charged
                            fee.chargedAt = start.addingTimeInterval(900)
                            fee.reason = .lateCancel
                        }
                        appointment.noShowFee = fee
                    }
                } else {
                    appointment.cancelledBy = .shop
                }
            }
            Self.refreshFeeReason(&appointment)
            appointments.append(appointment)
        }

        /// The fee's `reason` as the server writes it (like `FakeServer.refreshFeeReason`): what
        /// the charge was for once it was charged, otherwise the case that applies (or none).
        private static func refreshFeeReason(_ appointment: inout IzzyAPI.Appointment) {
            guard var fee = appointment.noShowFee, fee.status == .none else { return }
            let found = IzzyAPI.NoShowRule.feeCase(
                status: appointment.status, cancelledBy: appointment.cancelledBy, start: appointment.start,
                customerCancelledAt: fee.customerCancelledAt, lateCancelWindowMinutes: fee.lateCancelWindowMinutes,
                createdAt: appointment.createdAt
            )
            if case .chargeable(let reason) = found { fee.reason = reason } else { fee.reason = nil }
            appointment.noShowFee = fee
        }

        // MARK: Walk-ins

        /// Walk-ins: a quick cut (with a product now and then) or just products, with no appointment.
        private mutating func addWalkIns(of barber: Barber, profile: Profile, open: DateInterval, random: inout SeededRandom) {
            let quickCuts = catalog.offerings(forBarber: barber.id).filter {
                ($0.serviceID == "haircut" || $0.serviceID == "military-haircut") && $0.price.kind == .fixed
            }
            let openMinutes = Int(open.duration / 60)
            for _ in 0..<random.int(profile.walkIns) {
                let minute = 20 + random.int(0...max(0, openMinutes - 40))
                var items: [IzzyAPI.SaleItem] = []
                if random.chance(0.55), !quickCuts.isEmpty {
                    let cut = random.pick(quickCuts)
                    let name = catalog.service(withID: cut.serviceID)?.name ?? cut.serviceID
                    items.append(IzzyAPI.SaleItem(kind: .service, serviceId: cut.serviceID, name: name, unitCents: cut.price.cents))
                    if random.chance(0.2), let product = productItem(random: &random) { items.append(product) }
                } else {
                    if let product = productItem(random: &random) { items.append(product) }
                    if random.chance(0.3), let product = productItem(random: &random) { items.append(product) }
                }
                guard !items.isEmpty else { continue }
                addSale(
                    barber: barber, appointmentId: nil, customerName: nil, items: items,
                    soldAt: open.start.addingTimeInterval(TimeInterval(minute * 60)), random: &random
                )
            }
        }

        // MARK: Sales

        @discardableResult
        private mutating func addSale(
            barber: Barber, appointmentId: String?, customerName: String?, items: [IzzyAPI.SaleItem], soldAt: Date,
            random: inout SeededRandom
        ) -> IzzyAPI.Sale {
            saleNumber += 1
            let roll = random.next()
            let method: IzzyAPI.SaleMethod = roll < 0.55 ? .card : roll < 0.9 ? .cash : .other
            let sale = IzzyAPI.Sale(
                id: Self.uuid("b000", saleNumber),
                barberId: barber.id,
                barberName: barber.name,
                appointmentId: appointmentId,
                customerName: customerName,
                method: method,
                paymentIntentId: method == .card ? "pi_sample_history_\(saleNumber)" : nil,
                items: items,
                soldAt: soldAt
            )
            sales.append(sale)
            return sale
        }

        /// One of the shop's products, 1 or sometimes 2 of it; `nil` when the shop has none.
        private func productItem(random: inout SeededRandom) -> IzzyAPI.SaleItem? {
            guard !products.isEmpty else { return nil }
            let product = random.pick(products)
            return IzzyAPI.SaleItem(
                kind: .product, productId: product.id, name: product.name, quantity: random.chance(0.8) ? 1 : 2,
                unitCents: product.priceCents ?? typedProductCents
            )
        }

        private func pick(_ offerings: [Offering], weights: [String: Int], random: inout SeededRandom) -> Offering {
            let total = offerings.reduce(0) { $0 + (weights[$1.serviceID] ?? 0) }
            var roll = random.int(0...max(0, total - 1))
            for offering in offerings {
                roll -= weights[offering.serviceID] ?? 0
                if roll < 0 { return offering }
            }
            return offerings[0]
        }

        /// UUID-shaped, the same on every run: "00000000-0000-4000-a000-000000000001".
        static func uuid(_ group: String, _ number: Int) -> String {
            let digits = String(number)
            return "00000000-0000-4000-\(group)-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits
        }
    }
}

/// A small random number generator that gives the same numbers for the same text (FNV-1a for the
/// seed, then mulberry32), like the website demo's: sample data that's the same on every run.
struct SeededRandom {
    private var state: UInt32

    init(_ text: String) {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        state = hash
    }

    /// From 0 up to, not including, 1.
    mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var value = state
        value = (value ^ (value >> 15)) &* (value | 1)
        value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
        return Double(value ^ (value >> 14)) / 4_294_967_296
    }

    /// `true` with the chance `probability`.
    mutating func chance(_ probability: Double) -> Bool {
        next() < probability
    }

    /// A whole number in `range`, each as likely.
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + min(Int(next() * Double(range.count)), range.count - 1)
    }

    mutating func pick<Element>(_ items: [Element]) -> Element {
        items[int(0...(items.count - 1))]
    }
}
