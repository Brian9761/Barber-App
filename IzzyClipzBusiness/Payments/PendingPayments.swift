import Foundation

/// PaymentIntents the app created but hasn't heard a final answer about yet.
///
/// If the app is closed (or the network drops) after a card was tapped but
/// before the server confirmed the payment, the server still thinks it's
/// unpaid. The next time Take payment opens, the app asks the server again
/// about each one (`completePayment` is safe to repeat), so a payment that
/// went through still shows up and marks its appointment paid.
///
/// Only PaymentIntent IDs and times are kept: no amounts, cards or names.
@MainActor
final class PendingPayments {
    private let defaults: UserDefaults
    private let key = "pendingPaymentIntents"
    /// After this long a PaymentIntent that never succeeded is forgotten.
    static let maximumAge: TimeInterval = 48 * 3_600

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// PaymentIntent ID → when it was created.
    var entries: [String: Date] {
        let stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        return stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func add(_ paymentIntentId: String, at date: Date) {
        var stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        stored[paymentIntentId] = date.timeIntervalSince1970
        defaults.set(stored, forKey: key)
    }

    func remove(_ paymentIntentId: String) {
        var stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        guard stored.removeValue(forKey: paymentIntentId) != nil else { return }
        defaults.set(stored, forKey: key)
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }
}
