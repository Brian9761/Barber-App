import Foundation

/// The shop's full menu: services, the team, and who offers what at which price.
public struct Catalog: Sendable {
    public let services: [Service]
    public let barbers: [Barber]
    public let offerings: [Offering]

    public init(services: [Service], barbers: [Barber], offerings: [Offering]) {
        self.services = services
        self.barbers = barbers
        self.offerings = offerings
    }

    // MARK: Lookup

    public func service(withID id: String) -> Service? {
        services.first { $0.id == id }
    }

    public func barber(withID id: String) -> Barber? {
        barbers.first { $0.id == id }
    }

    public func offering(withID id: String) -> Offering? {
        offerings.first { $0.id == id }
    }

    // MARK: Services

    /// Categories that have at least one service, in menu order.
    public var categories: [ServiceCategory] {
        ServiceCategory.allCases.filter { category in
            services.contains { $0.category == category }
        }
    }

    public func services(in category: ServiceCategory) -> [Service] {
        services.filter { $0.category == category }
    }

    public var popularServices: [Service] {
        services.filter(\.isPopular)
    }

    /// Services a barber offers, in menu order.
    public func services(offeredBy barberID: String) -> [Service] {
        let offered = Set(offerings.lazy.filter { $0.barberID == barberID }.map(\.serviceID))
        return services.filter { offered.contains($0.id) }
    }

    /// Case- and accent-insensitive search across names, descriptions and categories.
    public func search(_ query: String) -> [Service] {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return services }
        return services.filter { service in
            let haystack = ([service.name, service.summary, service.category.title] + service.includes)
                .joined(separator: " ")
            return terms.allSatisfy { term in
                haystack.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    // MARK: Offerings

    /// Every barber's version of a service, cheapest first, then in team order.
    public func offerings(forService serviceID: String) -> [Offering] {
        offerings
            .filter { $0.serviceID == serviceID }
            .sorted { lhs, rhs in
                if lhs.price.cents != rhs.price.cents { return lhs.price.cents < rhs.price.cents }
                let lhsRank = barberRank(lhs.barberID), rhsRank = barberRank(rhs.barberID)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.durationMinutes < rhs.durationMinutes
            }
    }

    /// Everything a barber offers, in menu order.
    public func offerings(forBarber barberID: String) -> [Offering] {
        offerings
            .filter { $0.barberID == barberID }
            .sorted { lhs, rhs in
                let lhsRank = serviceRank(lhs.serviceID), rhsRank = serviceRank(rhs.serviceID)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.price.cents != rhs.price.cents { return lhs.price.cents < rhs.price.cents }
                return lhs.durationMinutes < rhs.durationMinutes
            }
    }

    /// Barbers who offer a service, in team order.
    public func barbers(offering serviceID: String) -> [Barber] {
        let ids = Set(offerings.lazy.filter { $0.serviceID == serviceID }.map(\.barberID))
        return barbers.filter { ids.contains($0.id) }
    }

    /// "$35–$45" across everyone who offers the service.
    public func priceSummary(forService serviceID: String) -> String {
        Price.summary(of: offerings.filter { $0.serviceID == serviceID }.map(\.price))
    }

    /// "45 min – 1 hr" across everyone who offers the service.
    public func durationSummary(forService serviceID: String) -> String {
        DurationText.range(minutes: offerings.filter { $0.serviceID == serviceID }.map(\.durationMinutes))
    }

    /// A barber's lowest price for a service, e.g. for "Haircut from $35" labels.
    /// `nil` when they don't offer it.
    public func lowestPrice(forService serviceID: String, barber barberID: String) -> Price? {
        offerings
            .filter { $0.serviceID == serviceID && $0.barberID == barberID }
            .map(\.price)
            .min()
    }

    /// The best way to book a service with whoever is free first.
    ///
    /// Squire only lets "any barber" bookings preselect a single menu item, so
    /// this picks the item the most barbers share. It's `nil` when fewer than
    /// two barbers share an item, since "first available" would be meaningless.
    public func firstAvailableOption(forService serviceID: String) -> FirstAvailableOption? {
        let groups = Dictionary(grouping: offerings.filter { $0.serviceID == serviceID }, by: \.squireServiceID)
        let best = groups
            .filter { $0.value.count >= 2 }
            .min { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                let lhsLowest = lhs.value.map(\.price.cents).min() ?? 0
                let rhsLowest = rhs.value.map(\.price.cents).min() ?? 0
                if lhsLowest != rhsLowest { return lhsLowest < rhsLowest }
                return lhs.key < rhs.key
            }
        guard let best else { return nil }
        let group = best.value
        return FirstAvailableOption(
            squireServiceID: best.key,
            serviceID: serviceID,
            barberIDs: barbers.map(\.id).filter { id in group.contains { $0.barberID == id } },
            priceLabel: Price.summary(of: group.map(\.price)),
            durationLabel: DurationText.range(minutes: group.map(\.durationMinutes))
        )
    }

    // MARK: Integrity

    /// Everything wrong with the data, as human-readable messages. Empty means valid.
    public func validationProblems() -> [String] {
        var problems: [String] = []

        func checkUnique(_ ids: [String], _ kind: String) {
            for (id, count) in Dictionary(grouping: ids, by: { $0 }).mapValues(\.count) where count > 1 {
                problems.append("Duplicate \(kind) ID '\(id)'")
            }
        }
        checkUnique(services.map(\.id), "service")
        checkUnique(barbers.map(\.id), "barber")
        checkUnique(offerings.map(\.id), "offering")

        for service in services {
            if service.name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Service '\(service.id)' has no name") }
            if service.summary.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Service '\(service.id)' has no summary") }
            if !offerings.contains(where: { $0.serviceID == service.id }) { problems.append("Nobody offers '\(service.id)'") }
        }
        for barber in barbers {
            if barber.name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Barber '\(barber.id)' has no name") }
            if !offerings.contains(where: { $0.barberID == barber.id }) { problems.append("'\(barber.id)' offers nothing") }
            if !Catalog.isURLSlug(barber.id) { problems.append("Barber ID '\(barber.id)' isn't a URL slug") }
        }
        for offering in offerings {
            if service(withID: offering.serviceID) == nil { problems.append("Offering '\(offering.id)' points at unknown service '\(offering.serviceID)'") }
            if barber(withID: offering.barberID) == nil { problems.append("Offering '\(offering.id)' points at unknown barber '\(offering.barberID)'") }
            if UUID(uuidString: offering.squireServiceID) == nil { problems.append("Offering '\(offering.id)' has an invalid Squire ID") }
        }
        // One Squire menu item is one service, whoever performs it.
        for (squireID, group) in Dictionary(grouping: offerings, by: \.squireServiceID) {
            if Set(group.map(\.serviceID)).count > 1 { problems.append("Squire item '\(squireID)' is mapped to several services") }
        }
        return problems
    }

    static func isURLSlug(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    // MARK: Ordering

    private func barberRank(_ id: String) -> Int {
        barbers.firstIndex { $0.id == id } ?? Int.max
    }

    private func serviceRank(_ id: String) -> Int {
        services.firstIndex { $0.id == id } ?? Int.max
    }
}

/// Booking a service with whichever barber is free first.
public struct FirstAvailableOption: Hashable, Sendable {
    public let squireServiceID: String
    public let serviceID: String
    /// The barbers Squire will choose from, in team order.
    public let barberIDs: [String]
    public let priceLabel: String
    public let durationLabel: String
}
