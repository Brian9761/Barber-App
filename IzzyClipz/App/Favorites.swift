import Foundation
import Observation

/// The client's favorite barber, remembered between launches.
@MainActor
@Observable
final class Favorites {
    private static let key = "favorites.barberID"

    private let defaults: UserDefaults
    private let catalog: Catalog
    private(set) var barberID: String?

    init(defaults: UserDefaults, catalog: Catalog = AppData.catalog) {
        self.defaults = defaults
        self.catalog = catalog
        let stored = defaults.string(forKey: Self.key)
        // Forget barbers who are no longer on the team.
        barberID = stored.flatMap { catalog.barber(withID: $0) }?.id
    }

    var barber: Barber? {
        barberID.flatMap { catalog.barber(withID: $0) }
    }

    func isFavorite(_ barberID: String) -> Bool {
        self.barberID == barberID
    }

    /// Makes a barber the favorite, or clears them if they already are.
    func toggle(_ barberID: String) {
        self.barberID = isFavorite(barberID) ? nil : barberID
        defaults.set(self.barberID, forKey: Self.key)
    }
}
